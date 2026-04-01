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
  validates :portfolio_withdrawal_rate,
            numericality: { greater_than: 0, less_than_or_equal_to: 100 },
            allow_nil: true
  validates :retirement_monthly_expenses,
            numericality: { greater_than: 0 },
            allow_nil: true
  validates :portfolio_growth_rate,
            numericality: { greater_than_or_equal_to: -20, less_than_or_equal_to: 50 },
            allow_nil: true
  validates :inflation_rate,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 20 },
            allow_nil: true

  # Monetary fields
  monetize :retirement_monthly_expenses,
           :current_annual_salary,
           :gesetzliche_rente_monthly,
           :riester_monthly,
           :ruerup_monthly,
           :betriebsrente_monthly,
           :other_pension_monthly,
           :monthly_contribution,
           :current_portfolio_value,
           :total_pension_income,
           :income_gap_monthly,
           :required_portfolio_value,
           :portfolio_gap,
           :after_tax_monthly_income,
           :monthly_living_expenses

  before_save :calculate_retirement_metrics
  after_save :build_auto_milestones, if: :saved_change_to_calculation_date?

  # Main calculation: Modified 4% rule for gap coverage
  def calculate_retirement_metrics
    return unless retirement_monthly_expenses

    # Step 1: Calculate total pension income
    self.total_pension_income = calculate_total_pension_income

    # Step 2: Calculate gap (what portfolio must cover)
    self.income_gap_monthly = [ retirement_monthly_expenses - total_pension_income, 0 ].max

    # Step 3: Apply withdrawal rate ONLY to the gap
    annual_gap = income_gap_monthly * 12
    withdrawal_rate = (portfolio_withdrawal_rate || 4.0) / 100.0

    self.required_portfolio_value = if income_gap_monthly > 0
      annual_gap / withdrawal_rate
    else
      0  # Pensions fully cover expenses!
    end

    # Step 4: Compare to current portfolio (scoped by scenario type)
    self.current_portfolio_value = scoped_portfolio_value
    self.portfolio_gap = required_portfolio_value - current_portfolio_value

    # Step 5: Project retirement date
    if can_retire_now?
      self.projected_retirement_date = calculation_date
    else
      self.projected_retirement_date = estimate_retirement_date
    end
  end

  # Sum all pension income sources
  def calculate_total_pension_income
    # For personal/joint scenarios with retirement_scenario_persons, use per-person income
    if retirement_scenario_persons.any? && !household?
      return retirement_scenario_persons.sum do |rsp|
        (rsp.state_pension_monthly || 0) + (rsp.post_retirement_income_monthly || 0)
      end + pension_sources_total + (other_pension_monthly || 0)
    end

    # Legacy/household calculation
    total = 0

    # State pension (Gesetzliche Rente)
    total += gesetzliche_rente_monthly if gesetzliche_rente_monthly.present?

    # German pension products from linked accounts
    total += pension_sources_total

    # Legacy manual fields (for backwards compatibility)
    total += riester_monthly if riester_monthly.present? && !has_pension_source_of_type?("riester")
    total += ruerup_monthly if ruerup_monthly.present? && !has_pension_source_of_type?("ruerup")
    total += betriebsrente_monthly if betriebsrente_monthly.present? && !has_pension_source_of_type?("betriebsrente")

    # Other pension sources
    total += other_pension_monthly if other_pension_monthly.present?

    total
  end

  # Total monthly income from linked pension accounts
  def pension_sources_total
    pension_sources.with_payout.sum(:expected_monthly_payout) || 0
  end

  def pension_sources_total_money
    Money.new(pension_sources_total, family.currency)
  end

  # Check if a pension source of a specific type is linked
  def has_pension_source_of_type?(subtype)
    pension_sources.joins(:account).where(accounts: { subtype: subtype }).exists?
  end

  # Get all German pension accounts for the family
  def available_german_pension_accounts
    family.accounts
          .active
          .where(accountable_type: "Investment")
          .where(subtype: RetirementScenarioPensionSource::GERMAN_PENSION_SUBTYPES)
          .order(:name)
  end

  # Build pension sources for all available German pension accounts
  # Auto-populates values from account data
  def build_pension_sources_for_accounts
    available_german_pension_accounts.each do |account|
      unless pension_sources.any? { |ps| ps.account_id == account.id }
        pension_source = pension_sources.build(account: account)
        pension_source.populate_from_account!
      end
    end
  end

  # Can retire with current portfolio?
  def can_retire_now?
    return false unless current_portfolio_value && required_portfolio_value
    current_portfolio_value >= required_portfolio_value
  end

  # Pensions fully cover expenses?
  def pension_self_sufficient?
    return false unless total_pension_income && retirement_monthly_expenses
    total_pension_income >= retirement_monthly_expenses
  end

  # Estimate when can retire (with compound interest if growth rate set)
  def estimate_retirement_date
    return nil if pension_self_sufficient?  # Already covered by pensions
    return nil unless portfolio_gap.present? && portfolio_gap > 0

    # Use compound interest projection if growth rate available
    if portfolio_growth_rate.present?
      estimate_retirement_date_with_growth
    else
      estimate_retirement_date_linear
    end
  end

  # Simple linear projection (fallback when no growth rate)
  def estimate_retirement_date_linear
    surplus = median_monthly_surplus
    return nil unless surplus > 0

    months_needed = (portfolio_gap / surplus).ceil
    calculation_date + months_needed.months
  rescue
    nil
  end

  # Calculate median monthly surplus (income - expenses)
  def median_monthly_surplus
    income = family.income_statement.median_income
    expense = family.income_statement.median_expense
    income - expense
  end

  # Annual expenses in retirement
  def annual_retirement_expenses
    return nil unless retirement_monthly_expenses
    Money.new(retirement_monthly_expenses * 12, family.currency)
  end

  # Annual pension income
  def annual_pension_income
    return nil unless total_pension_income
    Money.new(total_pension_income * 12, family.currency)
  end

  # Progress toward retirement goal (0-100%)
  def progress_percent
    return 100 if can_retire_now?
    return 0 unless required_portfolio_value.present? && required_portfolio_value > 0
    return 0 unless current_portfolio_value.present?

    (current_portfolio_value / required_portfolio_value * 100).round(1)
  end

  # Pension coverage ratio (what % of expenses do pensions cover?)
  def pension_coverage_percent
    return 0 unless retirement_monthly_expenses && retirement_monthly_expenses > 0
    return 100 if pension_self_sufficient?

    (total_pension_income / retirement_monthly_expenses * 100).round(1)
  end

  # Months until retirement
  def months_until_retirement
    return 0 if can_retire_now?
    return nil unless projected_retirement_date

    ((projected_retirement_date.year - calculation_date.year) * 12 +
     (projected_retirement_date.month - calculation_date.month))
  end

  # Years until retirement (display helper)
  def years_until_retirement
    return 0 if can_retire_now?
    return nil unless months_until_retirement

    (months_until_retirement / 12.0).round(1)
  end

  # Generate month-by-month portfolio projections with compound interest
  # Uses account-level growth rates where available, falling back to portfolio_growth_rate
  # Contribution is dynamic: changes at milestone dates (debt payoff, salary changes, etc.)
  def generate_projections(months: nil)
    months ||= months_until_retirement || 360  # Default to 30 years

    base_contribution = monthly_contribution || effective_monthly_savings
    base_living_expenses = effective_living_expenses.to_f
    base_income = effective_monthly_income.to_f
    inf_rate = (inflation_rate || 3.0) / 100.0
    fallback_rate = portfolio_growth_rate || 7.0

    # Pre-load milestones for efficient date lookups
    sorted_milestones = milestones.chronological.to_a

    # Pre-build pension cashout events
    cashout_events = build_cashout_events(fallback_rate)

    # Get accounts scoped by scenario type for projection
    accounts = scoped_accounts.to_a

    # Initialize account projectors with their values
    account_data = accounts.map do |account|
      projector = AccountProjector.new(account, fallback_growth_rate: fallback_rate)
      {
        projector: projector,
        value: projector.current_value,
        monthly_rate: projector.monthly_growth_rate,
        contribution_eligible: projector.contribution_eligible?
      }
    end

    # Calculate total contribution-eligible balance for weighted distribution
    eligible_total = account_data.select { |a| a[:contribution_eligible] }
                                 .sum { |a| a[:value] }

    projections = []
    active_adjustments = 0

    months.times do |month|
      projection_date = calculation_date + (month + 1).months

      # Expense inflation: expenses grow each year
      years_elapsed = month / 12
      inflation_factor = (1 + inf_rate) ** years_elapsed

      # Check if any milestones kick in this month
      sorted_milestones.each do |milestone|
        next unless milestone.date.year == projection_date.year && milestone.date.month == projection_date.month

        case milestone.milestone_type
        when "debt_payoff", "bauspar_phase_change"
          active_adjustments += (milestone.amount || 0)
        when "income_start"
          active_adjustments += (milestone.amount || 0)
        when "income_stop"
          active_adjustments -= (milestone.amount || 0)
        end
      end

      # Dynamic contribution: base + milestone adjustments, adjusted for expense inflation
      # As expenses grow with inflation, savings shrink (income stays flat in real terms)
      inflation_drag = base_living_expenses * (inflation_factor - 1)
      contribution = base_contribution + active_adjustments - inflation_drag
      contribution = [ contribution, 0 ].max

      total_return = 0
      cashout_injection = 0

      # Check for pension cashout lump sums this month
      cashout_events.each do |event|
        if event[:date].year == projection_date.year && event[:date].month == projection_date.month
          cashout_injection += event[:amount]
        end
      end

      # Project each account forward one month
      account_data.each do |data|
        growth = data[:value] * data[:monthly_rate]
        total_return += growth

        account_contribution = if data[:contribution_eligible] && eligible_total > 0
          (data[:value] / eligible_total) * contribution
        else
          0
        end

        data[:value] = data[:value] + growth + account_contribution
      end

      # Sum all account values + cashout injection
      portfolio_value = account_data.sum { |a| a[:value] } + cashout_injection

      # If there was a cashout, add it to the first eligible account for tracking
      if cashout_injection > 0 && account_data.any? { |a| a[:contribution_eligible] }
        first_eligible = account_data.find { |a| a[:contribution_eligible] }
        first_eligible[:value] += cashout_injection if first_eligible
      end

      eligible_total = account_data.select { |a| a[:contribution_eligible] }
                                   .sum { |a| a[:value] }

      can_retire = portfolio_value >= required_portfolio_value

      projections << {
        month: month + 1,
        date: projection_date,
        portfolio_value: portfolio_value,
        investment_return: total_return,
        contribution: contribution,
        cashout_injection: cashout_injection,
        can_retire: can_retire
      }
    end

    projections
  end

  # Total contributions over projection period
  def total_contributions_projected(months)
    contribution = monthly_contribution || median_monthly_surplus
    contribution * months
  end

  # Total investment returns over projection period
  def total_returns_projected(months)
    projections = generate_projections(months: months)
    projections.sum { |p| p[:investment_return] }
  end

  # Real vs nominal returns (accounting for inflation)
  def real_portfolio_growth_rate
    return nil unless portfolio_growth_rate && inflation_rate
    RetirementScenario::InterestCalculator.real_return(
      nominal_rate: portfolio_growth_rate,
      inflation_rate: inflation_rate
    )
  end

  # Improved retirement date with compound interest
  def estimate_retirement_date_with_growth
    return calculation_date if can_retire_now?
    return nil unless portfolio_gap.present? && portfolio_gap > 0

    projections = generate_projections(months: 480)  # Search up to 40 years
    retirement_projection = projections.find { |p| p[:can_retire] }
    retirement_projection ? retirement_projection[:date] : nil
  end

  # Apply explored retirement dates (from the interactive explorer)
  def apply_exploration!(params)
    params = params.to_h.with_indifferent_access

    transaction do
      if params[:salary_end_date].present?
        self.salary_end_date = Date.parse(params[:salary_end_date])
      end

      if params[:gesetzliche_rente_start_date].present?
        self.gesetzliche_rente_start_date = Date.parse(params[:gesetzliche_rente_start_date])
      end

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

      save! # Triggers calculate_retirement_metrics via before_save
    end
  end

  # Trigger recalculation (when family data changes)
  def recalculate!
    self.calculation_date = Date.today
    calculate_retirement_metrics
    save!
  end

  # ========================================
  # Income Stream Planning Methods
  # ========================================

  # Project total monthly income at any future date
  def project_income_at_date(date)
    breakdown = income_breakdown_at_date(date)
    breakdown.values.sum
  end

  # Detailed breakdown of income at a specific date
  def income_breakdown_at_date(date)
    breakdown = {
      salary: 0,
      state_pension: 0,
      private_pensions: 0,
      other: 0
    }

    # Salary (if before salary end date)
    if current_annual_salary.present? && current_annual_salary > 0
      if salary_end_date.nil? || date <= salary_end_date
        breakdown[:salary] = current_annual_salary / 12.0
      end
    end

    # State pension (Gesetzliche Rente) - if after start date
    if gesetzliche_rente_monthly.present? && gesetzliche_rente_monthly > 0
      if gesetzliche_rente_start_date.nil? || date >= gesetzliche_rente_start_date
        breakdown[:state_pension] = gesetzliche_rente_monthly
      end
    end

    # Private pensions from linked accounts (each with its own start date)
    pension_sources.with_payout.each do |pension_source|
      if pension_source.payout_start_date.nil? || date >= pension_source.payout_start_date
        breakdown[:private_pensions] += pension_source.expected_monthly_payout
      end
    end

    # Legacy manual fields (for backwards compatibility)
    if riester_monthly.present? && !has_pension_source_of_type?("riester")
      breakdown[:private_pensions] += riester_monthly
    end
    if ruerup_monthly.present? && !has_pension_source_of_type?("ruerup")
      breakdown[:private_pensions] += ruerup_monthly
    end
    if betriebsrente_monthly.present? && !has_pension_source_of_type?("betriebsrente")
      breakdown[:private_pensions] += betriebsrente_monthly
    end

    # Other pension sources
    if other_pension_monthly.present? && other_pension_monthly > 0
      if other_pension_start_date.nil? || date >= other_pension_start_date
        breakdown[:other] = other_pension_monthly
      end
    end

    breakdown
  end

  # Identify gap period between salary end and earliest pension start
  def gap_period
    return nil unless salary_end_date.present?

    # Find the earliest pension start date
    earliest_pension_start = earliest_pension_start_date
    return nil unless earliest_pension_start.present?

    # Gap exists if there's time between salary end and pension start
    gap_start = salary_end_date + 1.day
    gap_end = earliest_pension_start - 1.day

    return nil if gap_end < gap_start  # No gap

    gap_months = months_between(gap_start, gap_end)
    monthly_shortfall = retirement_monthly_expenses || 0

    {
      start_date: gap_start,
      end_date: gap_end,
      months: gap_months,
      monthly_shortfall: monthly_shortfall
    }
  end

  # Find the earliest date when any pension income starts
  def earliest_pension_start_date
    dates = []

    # State pension
    dates << gesetzliche_rente_start_date if gesetzliche_rente_start_date.present? && gesetzliche_rente_monthly.to_f > 0

    # Private pension sources
    pension_sources.with_payout.each do |ps|
      dates << ps.payout_start_date if ps.payout_start_date.present?
    end

    # Other pension
    dates << other_pension_start_date if other_pension_start_date.present? && other_pension_monthly.to_f > 0

    dates.compact.min
  end

  # Cash needed to bridge the gap period
  def gap_bridge_amount
    gap = gap_period
    return 0 unless gap

    gap[:months] * gap[:monthly_shortfall]
  end

  def gap_bridge_amount_money
    Money.new(gap_bridge_amount, family.currency)
  end

  # Can current portfolio cover the gap period?
  def can_bridge_gap?
    return true unless gap_period  # No gap = no problem
    return false unless current_portfolio_value.present?

    current_portfolio_value >= gap_bridge_amount
  end

  # Generate income timeline data for chart visualization
  def generate_income_timeline(years: 30)
    timeline = []
    start_date = calculation_date || Date.today
    months = years * 12

    months.times do |i|
      date = start_date + i.months
      breakdown = income_breakdown_at_date(date)
      total_income = breakdown.values.sum

      timeline << {
        date: date,
        month: i,
        salary: breakdown[:salary],
        state_pension: breakdown[:state_pension],
        private_pensions: breakdown[:private_pensions],
        other: breakdown[:other],
        total_income: total_income,
        expenses: retirement_monthly_expenses || 0,
        surplus_deficit: total_income - (retirement_monthly_expenses || 0),
        in_gap_period: in_gap_period?(date)
      }
    end

    timeline
  end

  # Check if a date falls within the gap period
  def in_gap_period?(date)
    gap = gap_period
    return false unless gap

    date >= gap[:start_date] && date <= gap[:end_date]
  end

  # Key income milestones (salary end, pension starts)
  def income_milestones
    milestones = []

    # Include per-person milestones for personal/joint scenarios
    if retirement_scenario_persons.any? && !household?
      milestones.concat(person_income_milestones)
    end

    # Salary end (legacy/household)
    if salary_end_date.present? && (household? || retirement_scenario_persons.empty?)
      milestones << {
        date: salary_end_date,
        type: :salary_end,
        label: "Salary ends",
        description: "Last month of salary income"
      }
    end

    # State pension start
    if gesetzliche_rente_start_date.present? && gesetzliche_rente_monthly.to_f > 0
      milestones << {
        date: gesetzliche_rente_start_date,
        type: :state_pension_start,
        label: "State pension starts",
        description: "Gesetzliche Rente begins",
        amount: gesetzliche_rente_monthly
      }
    end

    # Private pension sources
    pension_sources.with_payout.includes(:account).each do |ps|
      if ps.payout_start_date.present?
        milestones << {
          date: ps.payout_start_date,
          type: :private_pension_start,
          label: "#{ps.account.name} starts",
          description: "#{ps.pension_type_label} payments begin",
          amount: ps.expected_monthly_payout
        }
      end
    end

    # Other pension start
    if other_pension_start_date.present? && other_pension_monthly.to_f > 0
      milestones << {
        date: other_pension_start_date,
        type: :other_pension_start,
        label: "Other pension starts",
        description: "Additional pension income begins",
        amount: other_pension_monthly
      }
    end

    # Gap period
    gap = gap_period
    if gap
      milestones << {
        date: gap[:start_date],
        type: :gap_start,
        label: "Gap period starts",
        description: "No income - portfolio bridge needed",
        months: gap[:months]
      }
      milestones << {
        date: gap[:end_date],
        type: :gap_end,
        label: "Gap period ends",
        description: "Pension income begins"
      }
    end

    milestones.sort_by { |m| m[:date] }
  end

  # Summary: income at different life stages
  def income_at_today
    project_income_at_date(Date.today)
  end

  def income_at_today_money
    Money.new(income_at_today, family.currency)
  end

  def income_at_retirement
    return nil unless salary_end_date
    project_income_at_date(salary_end_date + 1.day)
  end

  def income_at_retirement_money
    return nil unless income_at_retirement
    Money.new(income_at_retirement, family.currency)
  end

  def income_at_full_pension
    # Income when all pensions are active (furthest pension start date + 1 month)
    dates = []
    dates << gesetzliche_rente_start_date if gesetzliche_rente_start_date.present?
    dates << other_pension_start_date if other_pension_start_date.present?
    pension_sources.with_payout.each { |ps| dates << ps.payout_start_date if ps.payout_start_date.present? }

    latest = dates.compact.max
    return calculate_total_pension_income unless latest

    project_income_at_date(latest)
  end

  def income_at_full_pension_money
    Money.new(income_at_full_pension, family.currency)
  end

  # ========================================
  # Person-Scoped Methods
  # ========================================

  # Portfolio value scoped by scenario type
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

  # Scoped accounts for projections
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

  # Per-person income breakdown at a date (for joint/personal scenarios)
  def person_income_at_date(date)
    return {} unless retirement_scenario_persons.any?

    retirement_scenario_persons.includes(:person).each_with_object({}) do |rsp, hash|
      hash[rsp.person.display_name] = rsp.income_at_date(date)
    end
  end

  # Combined income milestones from all persons (for joint scenarios)
  def person_income_milestones
    retirement_scenario_persons.includes(:person).flat_map(&:income_milestones).sort_by { |m| m[:date] }
  end

  # ========================================
  # Historical Snapshot Methods
  # ========================================

  # Create a snapshot of current state
  def create_snapshot!(notes: nil)
    # Calculate projected portfolio value based on previous snapshot's projection
    projected_value = calculate_projected_portfolio_for_today

    snapshots.create!(
      snapshot_date: Date.today,
      current_portfolio_value: current_portfolio_value,
      required_portfolio_value: required_portfolio_value,
      portfolio_gap: portfolio_gap,
      progress_percent: progress_percent,
      projected_retirement_date: projected_retirement_date,
      total_pension_income: total_pension_income,
      income_gap_monthly: income_gap_monthly,
      projected_portfolio_value: projected_value,
      growth_rate_assumption: portfolio_growth_rate,
      inflation_rate_assumption: inflation_rate,
      monthly_contribution_assumption: monthly_contribution || median_monthly_surplus,
      withdrawal_rate_assumption: portfolio_withdrawal_rate,
      notes: notes
    )
  end

  # Create snapshot if none exists for today
  def create_snapshot_if_needed!(notes: nil)
    return if snapshots.exists?(snapshot_date: Date.today)
    create_snapshot!(notes: notes)
  end

  # Get the most recent snapshot
  def latest_snapshot
    snapshots.reverse_chronological.first
  end

  # Calculate what portfolio value was projected for today based on earlier snapshots
  def calculate_projected_portfolio_for_today
    previous = snapshots.where("snapshot_date < ?", Date.today).reverse_chronological.first
    return nil unless previous

    months_elapsed = months_since(previous.snapshot_date)
    return previous.current_portfolio_value if months_elapsed <= 0

    # Use the growth rate and contribution from the previous snapshot
    growth_rate = previous.growth_rate_assumption || 7.0
    contribution = previous.monthly_contribution_assumption || 0
    monthly_rate = growth_rate / 100.0 / 12.0

    # Compound growth calculation
    portfolio = previous.current_portfolio_value
    months_elapsed.times do
      portfolio = portfolio * (1 + monthly_rate) + contribution
    end

    portfolio
  end

  # Calculate actual annualized growth rate between two dates
  def actual_growth_rate(start_date: nil, end_date: Date.today)
    start_snapshot = if start_date
      snapshots.find_by(snapshot_date: start_date)
    else
      snapshots.chronological.first
    end

    end_snapshot = snapshots.find_by(snapshot_date: end_date) || latest_snapshot
    return nil unless start_snapshot && end_snapshot
    return nil if start_snapshot == end_snapshot

    end_snapshot.actual_growth_rate_since(start_snapshot)
  end

  # Summary of assumption accuracy based on snapshots
  def assumption_accuracy_summary
    return nil if snapshots.count < 2

    first_snapshot = snapshots.chronological.first
    latest = latest_snapshot

    actual_rate = actual_growth_rate
    assumed_rate = first_snapshot.growth_rate_assumption

    {
      period_start: first_snapshot.snapshot_date,
      period_end: latest.snapshot_date,
      months: months_since(first_snapshot.snapshot_date),
      assumed_growth_rate: assumed_rate,
      actual_growth_rate: actual_rate,
      growth_rate_variance: actual_rate && assumed_rate ? (actual_rate - assumed_rate).round(2) : nil,
      tracking_status: latest.tracking_status,
      portfolio_variance: latest.portfolio_variance,
      portfolio_variance_percent: latest.portfolio_variance_percent
    }
  end

  # ========================================
  # Cash Flow & Obligations Methods
  # ========================================

  # Detect fixed monthly obligations from loan and bauspar accounts
  def fixed_obligations
    obligations = []

    family.accounts.active.where(accountable_type: "Loan").find_each do |account|
      loan = account.accountable
      payment = numeric_value(loan.monthly_payment) if loan.respond_to?(:monthly_payment)
      next unless payment&.positive?
      obligations << {
        name: account.name,
        monthly_amount: payment,
        end_date: loan.respond_to?(:maturity_date) ? loan.maturity_date : nil,
        account_id: account.id,
        type: :loan
      }
    end

    family.accounts.active.where(accountable_type: "BausparContract").find_each do |account|
      bauspar = account.accountable
      contribution = numeric_value(bauspar.monthly_contribution)
      next unless bauspar.phase == "saving" && contribution&.positive?
      obligations << {
        name: account.name,
        monthly_amount: contribution,
        end_date: bauspar.expected_allocation_date,
        account_id: account.id,
        type: :bauspar
      }
    end

    # Note: PrivateLoans are money YOU lent out — the monthly_payment is income
    # coming back to you, not an outgoing obligation. They are handled in
    # incoming_loan_payments instead.

    obligations
  end

  def total_fixed_obligations
    fixed_obligations.sum { |o| o[:monthly_amount].to_f }
  end

  # Income from private loans you gave out (money coming back to you)
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

  # Build a structured cash flow breakdown for the current month
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

  # After-tax monthly income: manual override or auto-calculated
  # Always returns a plain numeric value (not Money)
  def effective_monthly_income
    return after_tax_monthly_income.to_f if after_tax_monthly_income.present? && after_tax_monthly_income.to_f > 0

    # Try per-person salary sum
    if retirement_scenario_persons.any?
      person_income = retirement_scenario_persons.sum { |rsp| (rsp.current_annual_salary || 0).to_f / 12.0 }
      return person_income if person_income > 0
    end

    # Fallback to household salary
    return current_annual_salary.to_f / 12.0 if current_annual_salary.present? && current_annual_salary.to_f > 0

    # Last resort: median income from transactions
    val = family.income_statement.median_income rescue 0
    val.is_a?(Money) ? val.amount.to_f : val.to_f
  end

  # Living expenses: manual override or auto-calculated (total expenses minus detected obligations)
  # Always returns a plain numeric value (not Money)
  def effective_living_expenses
    return monthly_living_expenses.to_f if monthly_living_expenses.present? && monthly_living_expenses.to_f > 0

    # Auto-calculate: median expenses minus detected fixed obligations
    val = family.income_statement.median_expense rescue 0
    total_expenses = val.is_a?(Money) ? val.amount.to_f : val.to_f
    obligations = total_fixed_obligations.to_f
    [ total_expenses - obligations, 0 ].max
  end

  # Monthly savings = income - obligations - living expenses
  def effective_monthly_savings
    cash_flow_snapshot.monthly_savings
  end

  # ========================================
  # Milestone Methods
  # ========================================

  # Rebuild auto-detected milestones from account data
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
        replaced_loan = bauspar.replaces_loan_account&.accountable
        old_payment = numeric_value(replaced_loan&.monthly_payment) || 0
        bauspar_contribution = numeric_value(bauspar.monthly_contribution) || 0
        new_payment = bauspar.bauspar_loan_monthly_payment || 0

        # At allocation: old loan ends + Bauspar savings end → Bauspar loan starts
        # Cash flow change = old_loan_payment + bauspar_contribution - new_bauspar_loan_payment
        freed = old_payment + bauspar_contribution - new_payment

        milestones.create!(
          milestone_type: "bauspar_phase_change",
          date: allocation_date,
          label: "#{account.name} replaces #{bauspar.replaces_loan_account.name}",
          amount: freed.round(2),
          account: account,
          auto_detected: true
        )
      else
        # Standalone Bauspar: savings phase ends, contribution freed
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
      # Skip if this loan is being replaced by a Bauspar (already covered above)
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

  # All milestones sorted chronologically (auto + user-added)
  def all_milestones
    milestones.chronological.to_a
  end

  # Future milestones only
  def future_milestones
    milestones.future.chronological.to_a
  end

  # Monthly savings at a future date considering milestones
  def monthly_savings_at_date(date)
    base = effective_monthly_savings

    milestones.where("date <= ?", date).each do |milestone|
      case milestone.milestone_type
      when "debt_payoff", "bauspar_phase_change"
        base += (milestone.amount || 0)  # freed payment
      when "income_start"
        base += (milestone.amount || 0)
      when "income_stop"
        base -= (milestone.amount || 0)
      end
    end

    base
  end

  private

    def build_cashout_events(fallback_rate)
      events = []

      family.accounts.active.where(accountable_type: "Investment").includes(:accountable).each do |account|
        inv = account.accountable
        next unless inv.respond_to?(:allows_early_cashout?) && inv.allows_early_cashout?

        cashout_date = inv.effective_cashout_date
        next unless cashout_date.present? && cashout_date > Date.current

        amount = inv.projected_cashout_amount(fallback_growth_rate: fallback_rate)
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

    def numeric_value(val)
      return nil if val.nil?
      val.is_a?(Money) ? val.amount.to_f : val.to_f
    end

    def months_since(date)
      today = Date.today
      ((today.year - date.year) * 12) + (today.month - date.month)
    end

    def months_between(start_date, end_date)
      return 0 if end_date < start_date
      ((end_date.year - start_date.year) * 12) + (end_date.month - start_date.month) + 1
    end

    def monetizable_currency
      family&.currency
    end
end
