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
    self.current_portfolio_value = family.net_worth
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
  def build_pension_sources_for_accounts
    available_german_pension_accounts.each do |account|
      pension_sources.build(account: account) unless pension_sources.any? { |ps| ps.account_id == account.id }
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
    return nil unless portfolio_gap > 0

    # Use compound interest projection if growth rate available
    if portfolio_growth_rate.present?
      estimate_retirement_date_with_growth
    else
      estimate_retirement_date_linear
    end
  end

  # Simple linear projection (fallback when no growth rate)
  def estimate_retirement_date_linear
    monthly_surplus = family.income_statement.median_monthly_surplus
    return nil unless monthly_surplus > 0

    months_needed = (portfolio_gap / monthly_surplus).ceil
    calculation_date + months_needed.months
  rescue
    nil
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
    return 0 unless required_portfolio_value > 0

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
    contribution = monthly_contribution || family.income_statement.median_monthly_surplus
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
    contribution = monthly_contribution || family.income_statement.median_monthly_surplus
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
    return nil unless portfolio_gap > 0

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
end
