class Investment < ApplicationRecord
  include Accountable

  validates :expected_growth_rate, numericality: { greater_than_or_equal_to: -50, less_than_or_equal_to: 100 }, allow_nil: true

  SUBTYPES = {
    "brokerage" => { short: "Brokerage", long: "Brokerage" },
    "pension" => { short: "Pension", long: "Pension" },
    "retirement" => { short: "Retirement", long: "Retirement" },
    "mutual_fund" => { short: "Mutual Fund", long: "Mutual Fund" },
    "angel" => { short: "Angel", long: "Angel" },
    # German pension products
    "riester" => { short: "Riester", long: "Riester Pension (Riester-Rente)" },
    "ruerup" => { short: "Rürup", long: "Rürup Pension (Basisrente)" },
    "betriebsrente" => { short: "Betriebsrente", long: "Occupational Pension (Betriebliche Altersvorsorge)" },
    "gesetzliche_rente" => { short: "Gesetzl. Rente", long: "Statutory Pension (Gesetzliche Rentenversicherung)" },
    "versorgungswerk" => { short: "Versorgungswerk", long: "Professional Pension Fund (Berufsständisches Versorgungswerk)" },
    "private_rentenversicherung" => { short: "Private Rente", long: "Private Pension Insurance (Private Rentenversicherung)" }
    # US-specific pension products (commented out for European version)
    # "401k" => { short: "401(k)", long: "401(k)" },
    # "roth_401k" => { short: "Roth 401(k)", long: "Roth 401(k)" },
    # "529_plan" => { short: "529 Plan", long: "529 Plan" },
    # "hsa" => { short: "HSA", long: "Health Savings Account" },
    # "ira" => { short: "IRA", long: "Traditional IRA" },
    # "roth_ira" => { short: "Roth IRA", long: "Roth IRA" }
  }.freeze

  GERMAN_PENSION_SUBTYPES = %w[riester ruerup betriebsrente gesetzliche_rente versorgungswerk private_rentenversicherung].freeze

  # Pension types that allow early cash-out with surrender value
  CASHABLE_PENSION_SUBTYPES = %w[private_rentenversicherung].freeze

  # Pension types that never allow lump-sum payout (monthly pension only)
  PENSION_ONLY_SUBTYPES = %w[ruerup gesetzliche_rente versorgungswerk].freeze

  class << self
    def color
      "#1570EF"
    end

    def classification
      "asset"
    end

    def icon
      "line-chart"
    end
  end

  # Check if this investment is a German pension product
  def german_pension?
    account&.subtype.in?(GERMAN_PENSION_SUBTYPES)
  end

  # Expected monthly payout as Money object
  def expected_monthly_payout_money
    return nil unless expected_monthly_payout && account&.currency
    Money.new(expected_monthly_payout, account.currency)
  end

  # Years until retirement payout begins
  def years_until_retirement
    return nil unless retirement_date
    ((retirement_date - Date.today).to_f / 365.25).ceil
  end

  # Check if retirement date has passed (payout phase)
  def in_payout_phase?
    return false unless retirement_date
    Date.today >= retirement_date
  end

  # Check if this pension type allows early cash-out based on subtype
  def allows_early_cashout?
    return can_cash_out_early if can_cash_out_early.present?
    account&.subtype.in?(CASHABLE_PENSION_SUBTYPES)
  end

  # Check if this pension type only pays out as monthly pension (no lump sum)
  def pension_only_payout?
    account&.subtype.in?(PENSION_ONLY_SUBTYPES)
  end

  # Surrender value as Money object
  def surrender_value_money
    return nil unless surrender_value && account&.currency
    Money.new(surrender_value, account.currency)
  end

  # Effective current value - surrender value if cashable, otherwise balance
  def effective_cash_value
    if allows_early_cashout? && surrender_value.present?
      surrender_value_money
    else
      account&.balance_money
    end
  end

  # The date this pension will be cashed out (early or at retirement)
  def effective_cashout_date
    return nil unless allows_early_cashout?
    early_cashout_date || retirement_date
  end

  # Projected value at a future date, using growth rate and optional monthly contributions
  # monthly_contribution: amount paid into the contract each month (increases value over time)
  # contribution_end_date: when contributions stop (e.g., retirement or cashout date)
  def projected_value_at(date, fallback_growth_rate: 7.0, monthly_contribution: 0, contribution_end_date: nil)
    return 0 unless account&.balance.present?

    current = account.balance.to_f
    return current if current <= 0

    months = ((date - Date.current).to_f / 365.25 * 12).round
    return current if months <= 0

    rate = (expected_growth_rate || fallback_growth_rate).to_f

    if monthly_contribution.to_f > 0
      # Months during which contributions are made
      if contribution_end_date && contribution_end_date < date
        contrib_months = ((contribution_end_date - Date.current).to_f / 365.25 * 12).round.clamp(0, months)
      else
        contrib_months = months
      end

      # Phase 1: growth with contributions
      result = RetirementScenario::InterestCalculator.future_value_with_contributions(
        principal: current,
        annual_rate: rate,
        monthly_contribution: monthly_contribution.to_f,
        months: contrib_months
      )

      # Phase 2: growth without contributions (if contributions end before target date)
      remaining_months = months - contrib_months
      if remaining_months > 0
        RetirementScenario::InterestCalculator.compound_interest(
          principal: result[:final_balance],
          annual_rate: rate,
          years: remaining_months / 12.0
        )
      else
        result[:final_balance]
      end
    else
      # No contributions — pure compound growth
      rate_decimal = rate / 100.0
      current * ((1 + rate_decimal) ** (months / 12.0))
    end
  end

  # Projected cashout amount at the effective cashout date
  def projected_cashout_amount(fallback_growth_rate: 7.0, monthly_contribution: 0)
    date = effective_cashout_date
    return 0 unless date.present?

    if has_surrender_value && surrender_value.present?
      surrender_value.to_f
    else
      projected_value_at(date, fallback_growth_rate: fallback_growth_rate, monthly_contribution: monthly_contribution)
    end
  end
end
