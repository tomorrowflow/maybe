module RetirementScenario::InterestCalculator
  # Compound interest for savings/investments
  # FV = PV * (1 + r)^t
  def self.compound_interest(principal:, annual_rate:, years:)
    rate_decimal = annual_rate / 100.0
    principal * (1 + rate_decimal)**years
  end

  # Future value with regular monthly contributions
  # Uses month-by-month calculation for accuracy
  def self.future_value_with_contributions(principal:, annual_rate:, monthly_contribution:, months:)
    monthly_rate = annual_rate / 100.0 / 12.0
    balance = principal
    total_returns = 0

    months.times do
      interest = balance * monthly_rate
      total_returns += interest
      balance = balance + interest + monthly_contribution
    end

    {
      final_balance: balance,
      total_contributions: monthly_contribution * months,
      total_returns: total_returns
    }
  end

  # Calculate required monthly contribution to reach goal
  # Rearrangement of FV annuity formula
  def self.required_monthly_contribution(current_value:, target_value:, annual_rate:, months:)
    return 0 if current_value >= target_value

    monthly_rate = annual_rate / 100.0 / 12.0

    # Account for growth of existing principal
    future_value_of_current = current_value * (1 + monthly_rate)**months

    # Remaining gap after current portfolio grows
    remaining_gap = target_value - future_value_of_current
    return 0 if remaining_gap <= 0

    # Monthly contribution needed (FV of annuity formula rearranged)
    if monthly_rate.zero?
      remaining_gap / months
    else
      remaining_gap * monthly_rate / ((1 + monthly_rate)**months - 1)
    end
  end

  # Real return after inflation
  # Fisher equation: (1 + nominal) / (1 + inflation) - 1
  def self.real_return(nominal_rate:, inflation_rate:)
    ((1 + nominal_rate / 100.0) / (1 + inflation_rate / 100.0) - 1) * 100
  end
end
