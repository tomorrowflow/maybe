class RetirementScenario < ApplicationRecord
  include Monetizable

  belongs_to :family
  belongs_to :person, optional: true
  has_many :pension_sources, class_name: "RetirementScenarioPensionSource", dependent: :destroy
  has_many :snapshots, class_name: "RetirementScenarioSnapshot", dependent: :destroy
  has_many :retirement_scenario_persons, dependent: :destroy
  has_many :scenario_persons, through: :retirement_scenario_persons, source: :person
  has_many :milestones, class_name: "RetirementScenarioMilestone", dependent: :destroy
  has_many :linked_payments, class_name: "RetirementScenarioLinkedPayment", dependent: :destroy

  accepts_nested_attributes_for :pension_sources, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :retirement_scenario_persons, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :milestones, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :linked_payments, allow_destroy: true, reject_if: :all_blank

  enum :scenario_type, { household: "household", personal: "personal", joint: "joint" }, default: :household

  validates :name, presence: true
  validates :calculation_date, presence: true
  validates :retirement_monthly_expenses,
            numericality: { greater_than: 0 },
            allow_nil: true
  validates :portfolio_growth_rate,
            numericality: { greater_than_or_equal_to: -20, less_than_or_equal_to: 50 },
            allow_nil: true
  validates :portfolio_growth_std_dev,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 50 },
            allow_nil: true
  validates :inflation_rate,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 20 },
            allow_nil: true
  validates :simulation_count,
            numericality: { greater_than: 0, less_than_or_equal_to: 5000 },
            allow_nil: true
  validates :target_age,
            numericality: { greater_than: 0, less_than_or_equal_to: 120 },
            allow_nil: true

  monetize :retirement_monthly_expenses,
           :monthly_contribution,
           :current_portfolio_value,
           :total_pension_income,
           :after_tax_monthly_income,
           :monthly_living_expenses

  after_save :build_auto_milestones, if: :saved_change_to_calculation_date?

  # ========================================
  # Monte Carlo Simulation
  # ========================================

  def enqueue_monte_carlo!
    return if monte_carlo_running? || monte_carlo_pending?
    update_columns(monte_carlo_status: "pending")
    RunMonteCarloJob.perform_later(id)
  end

  def run_monte_carlo!
    update_columns(monte_carlo_status: "running")

    self.current_portfolio_value = scoped_portfolio_value
    self.current_savings_value = scoped_savings_value
    self.total_pension_income = calculate_total_pension_income

    engine = RetirementScenario::MonteCarloEngine.new(self)
    results = engine.run

    update!(
      monte_carlo_success_rate: results[:success_rate],
      monte_carlo_results: results,
      monte_carlo_ran_at: Time.current,
      monte_carlo_status: "completed",
      current_portfolio_value: current_portfolio_value,
      current_savings_value: current_savings_value,
      total_pension_income: total_pension_income
    )

    results
  rescue => e
    update_columns(monte_carlo_status: "failed")
    Rails.logger.error("Monte Carlo simulation failed for scenario #{id}: #{e.message}")
    raise
  end

  def monte_carlo_stale?
    monte_carlo_ran_at.nil? || updated_at > monte_carlo_ran_at
  end

  def monte_carlo_pending?
    monte_carlo_status == "pending"
  end

  def monte_carlo_running?
    monte_carlo_status == "running"
  end

  def monte_carlo_completed?
    monte_carlo_status == "completed"
  end

  def monte_carlo_failed?
    monte_carlo_status == "failed"
  end

  def recalculate!
    update!(calculation_date: Date.today)
    enqueue_monte_carlo!
  end

  # ========================================
  # Income Timeline
  # ========================================

  def enqueue_income_timeline!
    return if income_timeline_status == "running"
    update_columns(income_timeline_status: "pending")
    BuildIncomeTimelineJob.perform_later(id)
  end

  def income_timeline_running?
    income_timeline_status == "running"
  end

  def income_timeline_completed?
    income_timeline_status == "completed"
  end

  def parsed_income_timeline_results
    return nil unless income_timeline_results.present? && income_timeline_results != {}
    data = income_timeline_results
    data = JSON.parse(data) while data.is_a?(String)
    return nil unless data.is_a?(Hash)
    data.deep_symbolize_keys
  rescue
    nil
  end

  # ========================================
  # Sweet Spot Analysis
  # ========================================

  def enqueue_sweet_spot!
    return if sweet_spot_running?
    update_columns(sweet_spot_status: "pending")
    RunSweetSpotAnalysisJob.perform_later(id)
  end

  def sweet_spot_running?
    sweet_spot_status == "running"
  end

  def sweet_spot_pending?
    sweet_spot_status == "pending"
  end

  def sweet_spot_completed?
    sweet_spot_status == "completed"
  end

  def parsed_sweet_spot_results
    return nil unless sweet_spot_results.present? && sweet_spot_results != {}
    data = sweet_spot_results
    # Handle double-encoded JSON (string stored in JSONB)
    data = JSON.parse(data) while data.is_a?(String)
    return nil unless data.is_a?(Hash)
    data.deep_symbolize_keys
  rescue
    nil
  end

  # ========================================
  # Pension Income
  # ========================================

  def calculate_total_pension_income
    person_pensions = retirement_scenario_persons.sum { |rsp|
      (rsp.state_pension_monthly || 0) + (rsp.post_retirement_income_monthly || 0)
    }
    person_pensions + pension_sources_total
  end

  def pension_sources_total
    pension_sources.with_payout.sum(:expected_monthly_payout) || 0
  end

  def pension_sources_total_money
    Money.new(pension_sources_total, family.currency)
  end

  def available_german_pension_accounts
    family.accounts
          .active
          .where(accountable_type: "Investment")
          .where(subtype: RetirementScenarioPensionSource::GERMAN_PENSION_SUBTYPES)
          .order(:name)
  end

  def build_pension_sources_for_accounts
    available_german_pension_accounts.each do |account|
      unless pension_sources.any? { |ps| ps.account_id == account.id }
        pension_source = pension_sources.build(account: account)
        pension_source.populate_from_account!
      end
    end
  end

  # ========================================
  # Portfolio Scoping
  # ========================================

  def scoped_portfolio_value
    case scenario_type
    when "household"
      family.balance_sheet.net_worth
    when "personal"
      return family.balance_sheet.net_worth unless person.present?
      family.accounts.active.for_person(person).sum(:balance)
    when "joint"
      person_ids = retirement_scenario_persons.pluck(:person_id)
      return family.balance_sheet.net_worth if person_ids.empty?
      family.accounts.active
        .left_joins(:account_persons)
        .where(
          "accounts.ownership_type = ? OR account_persons.person_id IN (?)",
          Account.ownership_types[:household], person_ids
        )
        .distinct
        .sum(:balance)
    else
      family.balance_sheet.net_worth
    end
  end

  def scoped_accounts
    case scenario_type
    when "personal"
      person.present? ? family.accounts.active.for_person(person) : family.accounts.active
    when "joint"
      person_ids = retirement_scenario_persons.pluck(:person_id)
      if person_ids.any?
        family.accounts.active
          .left_joins(:account_persons)
          .where(
            "accounts.ownership_type = ? OR account_persons.person_id IN (?)",
            Account.ownership_types[:household], person_ids
          )
          .distinct
      else
        family.accounts.active
      end
    else
      family.accounts.active
    end
  end

  # Savings pool: depository accounts (checking, savings, fixed deposit, call money)
  def scoped_savings_value
    scoped_accounts.where(accountable_type: "Depository").sum(:balance).to_f
  end

  # Investment pool: everything liquid except properties and depositories
  # Properties are illiquid wealth — shown separately but not drawn from
  def scoped_investment_value
    liquid_types = %w[Investment Crypto BausparContract PrivateLoan OtherAsset]
    scoped_accounts.where(accountable_type: liquid_types).sum(:balance).to_f
  end

  # Illiquid wealth (properties) — shown as reference, not part of simulation pools
  def scoped_illiquid_value
    scoped_accounts.where(accountable_type: "Property").sum(:balance).to_f
  end

  # Weighted average interest rate across depository accounts
  def weighted_savings_rate
    accounts = scoped_accounts.where(accountable_type: "Depository").includes(:accountable).to_a
    total = accounts.sum { |a| a.balance.to_f }
    return 1.0 if total <= 0
    weighted = accounts.sum { |a| a.balance.to_f * (a.accountable.interest_rate || 1.0) }
    weighted / total
  end

  # ========================================
  # Cash Flow & Obligations
  # ========================================

  def fixed_obligations
    obligations = []

    # Build a map of loan_id → bauspar_allocation_date for loans being replaced
    bauspar_replacements = {}
    family.accounts.active.where(accountable_type: "BausparContract").find_each do |account|
      bauspar = account.accountable
      if bauspar.respond_to?(:replaces_loan_account_id) && bauspar.replaces_loan_account_id.present?
        bauspar_replacements[bauspar.replaces_loan_account_id] = bauspar.expected_allocation_date
      end
    end

    family.accounts.active.where(accountable_type: "Loan").find_each do |account|
      loan = account.accountable
      payment = numeric_value(loan.monthly_payment) if loan.respond_to?(:monthly_payment)
      next unless payment&.positive?

      # If this loan is being replaced by a Bauspar, it ends at allocation date
      end_date = loan.respond_to?(:maturity_date) ? loan.maturity_date : nil
      end_date ||= bauspar_replacements[account.id]

      obligations << {
        name: account.name,
        monthly_amount: payment,
        end_date: end_date,
        account_id: account.id,
        type: :loan
      }
    end

    family.accounts.active.where(accountable_type: "BausparContract").find_each do |account|
      bauspar = account.accountable

      # Saving phase contribution
      contribution = numeric_value(bauspar.monthly_contribution)
      if bauspar.phase == "saving" && contribution&.positive?
        obligations << {
          name: "#{account.name} (savings)",
          monthly_amount: contribution,
          end_date: bauspar.expected_allocation_date,
          account_id: account.id,
          type: :bauspar
        }
      end

      # Future Bauspar loan phase (starts at allocation, term from fixed repayment)
      if bauspar.phase == "saving" && bauspar.expected_allocation_date.present?
        loan_payment = bauspar.bauspar_loan_monthly_payment
        if loan_payment&.positive?
          term_months = bauspar.bauspar_loan_term_months
          obligations << {
            name: "#{account.name} (loan)",
            monthly_amount: loan_payment.round(2),
            start_date: bauspar.expected_allocation_date,
            end_date: bauspar.expected_allocation_date + term_months.months,
            account_id: account.id,
            type: :bauspar_loan
          }
        end
      end
    end

    obligations
  end

  def total_fixed_obligations
    fixed_obligations.sum { |o| o[:monthly_amount].to_f }
  end

  def incoming_loan_payments
    payments = []

    family.accounts.active.where(accountable_type: "PrivateLoan").find_each do |account|
      loan = account.accountable
      payment = numeric_value(loan.monthly_payment) if loan.respond_to?(:monthly_payment)
      next unless payment&.positive?
      payments << {
        name: account.name,
        monthly_amount: payment,
        end_date: loan.respond_to?(:maturity_date) ? loan.maturity_date : nil,
        account_id: account.id,
        type: :private_loan_income
      }
    end

    payments
  end

  def total_incoming_loan_payments
    incoming_loan_payments.sum { |p| p[:monthly_amount].to_f }
  end

  def effective_monthly_income
    return after_tax_monthly_income.to_f if after_tax_monthly_income.present? && after_tax_monthly_income.to_f > 0

    if retirement_scenario_persons.any?
      person_income = retirement_scenario_persons.sum { |rsp| (rsp.current_annual_salary || 0).to_f / 12.0 }
      return person_income if person_income > 0
    end

    val = family.income_statement.median_income rescue 0
    val.is_a?(Money) ? val.amount.to_f : val.to_f
  end

  def effective_living_expenses
    return monthly_living_expenses.to_f if monthly_living_expenses.present? && monthly_living_expenses.to_f > 0

    val = family.income_statement.median_expense rescue 0
    total_expenses = val.is_a?(Money) ? val.amount.to_f : val.to_f
    obligations = total_fixed_obligations.to_f
    [ total_expenses - obligations, 0 ].max
  end

  def effective_monthly_savings
    cash_flow_snapshot.monthly_savings
  end

  def cash_flow_snapshot
    income = effective_monthly_income + total_incoming_loan_payments
    obligations = total_fixed_obligations
    living = effective_living_expenses

    CashFlowSnapshot.new(
      monthly_income: income,
      fixed_obligations: obligations,
      living_expenses: living,
      obligation_details: fixed_obligations,
      incoming_payments: incoming_loan_payments,
      currency: family.currency
    )
  end

  # ========================================
  # Milestones
  # ========================================

  def build_auto_milestones
    milestones.auto_detected.delete_all

    # Loan payoff milestones
    family.accounts.active.where(accountable_type: %w[Loan PrivateLoan]).find_each do |account|
      loan = account.accountable
      next unless loan.respond_to?(:maturity_date) && loan.maturity_date.present?
      next unless loan.respond_to?(:monthly_payment) && loan.monthly_payment&.positive?

      milestones.create!(
        milestone_type: "debt_payoff",
        date: loan.maturity_date,
        label: "#{account.name} paid off",
        amount: numeric_value(loan.monthly_payment),
        account: account,
        auto_detected: true
      )
    end

    # Bauspar lifecycle milestones
    family.accounts.active.where(accountable_type: "BausparContract").find_each do |account|
      bauspar = account.accountable
      next unless bauspar.phase == "saving" && bauspar.expected_allocation_date.present?

      allocation_date = bauspar.expected_allocation_date

      if bauspar.replaces_loan?
        new_payment = bauspar.bauspar_loan_monthly_payment || 0

        # The milestone represents the NEW Bauspar loan payment that starts.
        # The old loan payment and Bauspar contribution already drop off via
        # fixed_obligations end_dates. We store the new payment as a NEGATIVE
        # amount (increases expenses) so the timeline builder adds it correctly.
        milestones.create!(
          milestone_type: "bauspar_phase_change",
          date: allocation_date,
          label: "#{account.name} replaces #{bauspar.replaces_loan_account.name}",
          amount: -new_payment.round(2),
          account: account,
          auto_detected: true
        )

        # Bauspar loan payoff — term calculated from fixed repayment amount
        term_months = bauspar.bauspar_loan_term_months
        bauspar_loan_end = allocation_date + term_months.months
        milestones.create!(
          milestone_type: "debt_payoff",
          date: bauspar_loan_end,
          label: "#{account.name} loan paid off",
          amount: new_payment.round(2),
          account: account,
          auto_detected: true
        )
      else
        milestones.create!(
          milestone_type: "bauspar_phase_change",
          date: allocation_date,
          label: "#{account.name} allocation",
          amount: numeric_value(bauspar.monthly_contribution),
          account: account,
          auto_detected: true
        )
      end
    end

    # Loan fixed-rate period end milestones (Zinsbindung)
    family.accounts.active.where(accountable_type: "Loan").find_each do |account|
      loan = account.accountable
      next unless loan.respond_to?(:fixed_rate_end_date) && loan.fixed_rate_end_date.present?
      next if family.accounts.active.where(accountable_type: "BausparContract")
                .any? { |ba| ba.accountable.replaces_loan_account_id == account.id }

      milestones.create!(
        milestone_type: "custom",
        date: loan.fixed_rate_end_date,
        label: "#{account.name} fixed rate ends (Zinsbindung)",
        amount: nil,
        account: account,
        auto_detected: true
      )
    end
  end

  def all_milestones
    milestones.chronological.to_a
  end

  def future_milestones
    milestones.future.chronological.to_a
  end

  def monthly_savings_at_date(date)
    base = effective_monthly_savings

    milestones.where("date <= ?", date).each do |milestone|
      case milestone.milestone_type
      when "debt_payoff", "bauspar_phase_change"
        base += (milestone.amount || 0)
      when "income_start"
        base += (milestone.amount || 0)
      when "income_stop"
        base -= (milestone.amount || 0)
      end
    end

    base
  end

  # ========================================
  # Snapshots
  # ========================================

  def create_snapshot!(notes: nil)
    snapshots.create!(
      snapshot_date: Date.today,
      current_portfolio_value: scoped_portfolio_value,
      total_pension_income: calculate_total_pension_income,
      monte_carlo_success_rate: monte_carlo_success_rate,
      growth_rate_assumption: portfolio_growth_rate,
      growth_std_dev_assumption: portfolio_growth_std_dev,
      inflation_rate_assumption: inflation_rate,
      monthly_contribution_assumption: monthly_contribution || effective_monthly_savings,
      simulation_count_assumption: simulation_count,
      target_age_assumption: target_age,
      notes: notes
    )
  end

  def create_snapshot_if_needed!(notes: nil)
    return if snapshots.exists?(snapshot_date: Date.today)
    create_snapshot!(notes: notes)
  end

  def latest_snapshot
    snapshots.reverse_chronological.first
  end

  # ========================================
  # Exploration
  # ========================================

  def apply_exploration!(params)
    params = params.to_h.with_indifferent_access

    transaction do
      params[:person_retirement_dates]&.each do |rsp_id, date_str|
        next if date_str.blank?
        rsp = retirement_scenario_persons.find(rsp_id)
        new_date = Date.parse(date_str)
        rsp.update!(salary_end_date: new_date, target_retirement_date: new_date)
      end

      params[:pension_payout_dates]&.each do |ps_id, date_str|
        next if date_str.blank?
        ps = pension_sources.find(ps_id)
        ps.update!(payout_start_date: Date.parse(date_str))
      end

      if params[:retirement_monthly_expenses].present?
        self.retirement_monthly_expenses = params[:retirement_monthly_expenses].to_f
      end

      if params[:monthly_contribution].present?
        self.monthly_contribution = params[:monthly_contribution].to_f
      end

      save!
    end

    enqueue_monte_carlo!
  end

  # ========================================
  # Cashout Events (for Monte Carlo engine)
  # ========================================

  def build_cashout_events(fallback_rate = nil)
    fallback_rate ||= portfolio_growth_rate || 7.0
    events = []

    family.accounts.active.where(accountable_type: "Investment").includes(:accountable).each do |account|
      inv = account.accountable
      next unless inv.respond_to?(:allows_early_cashout?) && inv.allows_early_cashout?

      cashout_date = inv.effective_cashout_date
      next unless cashout_date.present? && cashout_date > Date.current

      # Include monthly contributions into the projected value
      monthly_contrib = find_linked_contribution_for(account)
      amount = inv.projected_cashout_amount(
        fallback_growth_rate: fallback_rate,
        monthly_contribution: monthly_contrib
      )
      next unless amount > 0

      events << {
        date: cashout_date,
        amount: amount,
        account_name: account.name,
        account_id: account.id
      }
    end

    events
  end

  # Find monthly contribution for an account.
  # Priority: linked payment > fixed obligation > investment's own monthly_contribution field
  def find_linked_contribution_for(account)
    # From linked payments in wizard
    linked = linked_payments.linked_to_account.find_by(account_id: account.id)
    return linked.monthly_amount.to_f if linked&.monthly_amount.present?

    # From detected fixed obligations (loans, Bauspar)
    obligation = fixed_obligations.find { |o| o[:account_id] == account.id }
    return obligation[:monthly_amount].to_f if obligation

    # From the investment's own field (e.g., employer-paid contributions)
    if account.accountable.respond_to?(:monthly_contribution) && account.accountable.monthly_contribution.present?
      return account.accountable.monthly_contribution.to_f
    end

    0
  end

  private

    def numeric_value(val)
      return nil if val.nil?
      val.is_a?(Money) ? val.amount.to_f : val.to_f
    end

    def monetizable_currency
      family&.currency
    end
end
