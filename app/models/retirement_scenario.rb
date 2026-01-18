class RetirementScenario < ApplicationRecord
  include Monetizable

  belongs_to :family
  has_many :pension_sources, class_name: "RetirementScenarioPensionSource", dependent: :destroy

  accepts_nested_attributes_for :pension_sources, allow_destroy: true, reject_if: :all_blank

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
           :portfolio_gap

  before_save :calculate_retirement_metrics

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

    # Step 4: Compare to current portfolio
    self.current_portfolio_value = family.balance_sheet.net_worth
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
  def generate_projections(months: nil)
    months ||= months_until_retirement || 360  # Default to 30 years

    portfolio_value = current_portfolio_value
    contribution = monthly_contribution || median_monthly_surplus
    monthly_growth_rate = (portfolio_growth_rate || 7.0) / 100.0 / 12.0

    projections = []

    months.times do |month|
      # Apply monthly investment return
      investment_return = portfolio_value * monthly_growth_rate

      # Add contribution
      portfolio_value = portfolio_value + investment_return + contribution

      # Check if can retire at this point
      can_retire = portfolio_value >= required_portfolio_value

      projections << {
        month: month + 1,
        date: calculation_date + (month + 1).months,
        portfolio_value: portfolio_value,
        investment_return: investment_return,
        contribution: contribution,
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

    # Salary end
    if salary_end_date.present?
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

  private

    def months_between(start_date, end_date)
      return 0 if end_date < start_date
      ((end_date.year - start_date.year) * 12) + (end_date.month - start_date.month) + 1
    end

    def monetizable_currency
      family&.currency
    end
end
