# Provides interest-based balance projection for accounts with start dates and interest rates.
# Include this concern in accountable types that track interest (Loan, PrivateLoan, OtherLiability, etc.)
#
# Required attributes on the model:
# - interest_rate (decimal, annual percentage)
# - start_date (date)
# - One of: principal_amount, initial_balance, or use account.first_valuation_amount
module InterestProjectable
  extend ActiveSupport::Concern

  included do
    validates :interest_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  end

  # Calculate the expected current balance based on principal + accumulated interest
  # from start_date to today using compound interest
  #
  # @param compounding [Symbol] :monthly, :daily, or :annual
  # @return [BigDecimal, nil] Expected balance in account currency
  def expected_current_balance(compounding: :monthly)
    return nil unless can_project_balance?

    principal = principal_for_projection
    return nil unless principal

    months_elapsed = months_since_start
    return principal if months_elapsed <= 0 || interest_rate.nil? || interest_rate.zero?

    case compounding
    when :monthly
      calculate_monthly_compound(principal, months_elapsed)
    when :daily
      calculate_daily_compound(principal, days_since_start)
    when :annual
      calculate_annual_compound(principal, years_since_start)
    else
      calculate_monthly_compound(principal, months_elapsed)
    end
  end

  # Expected balance as Money object
  def expected_current_balance_money(compounding: :monthly)
    expected = expected_current_balance(compounding: compounding)
    return nil unless expected && account&.currency

    Money.new(expected, account.currency)
  end

  # Difference between expected balance (with interest) and actual current balance
  # Positive = actual is higher than expected (over-projected or extra payments for assets)
  # Negative = actual is lower than expected (under-projected or missed payments)
  def balance_variance
    return nil unless expected_current_balance && account

    account.balance - expected_current_balance
  end

  def balance_variance_money
    return nil unless balance_variance && account&.currency

    Money.new(balance_variance, account.currency)
  end

  # Percentage variance from expected
  def balance_variance_percent
    return nil unless expected_current_balance && expected_current_balance != 0

    ((balance_variance / expected_current_balance) * 100).round(2)
  end

  # Check if balance is within expected range (±5% by default)
  def balance_within_expected?(tolerance_percent: 5)
    return true unless balance_variance_percent

    balance_variance_percent.abs <= tolerance_percent
  end

  # Months elapsed since start_date
  def months_since_start
    return 0 unless start_date_for_projection

    start = start_date_for_projection
    today = Date.current

    return 0 if today < start

    ((today.year - start.year) * 12) + (today.month - start.month)
  end

  # Days elapsed since start_date
  def days_since_start
    return 0 unless start_date_for_projection

    days = (Date.current - start_date_for_projection).to_i
    [ days, 0 ].max
  end

  # Years elapsed since start_date (as decimal)
  def years_since_start
    days_since_start / 365.25
  end

  # Check if we have enough data to project
  def can_project_balance?
    start_date_for_projection.present? && principal_for_projection.present?
  end

  private

    # Override in including class if the date field has a different name
    def start_date_for_projection
      if respond_to?(:start_date) && start_date.present?
        start_date
      elsif respond_to?(:opening_date) && opening_date.present?
        opening_date
      elsif respond_to?(:acquisition_date) && acquisition_date.present?
        acquisition_date
      elsif respond_to?(:purchase_date) && purchase_date.present?
        purchase_date
      elsif respond_to?(:contract_start_date) && contract_start_date.present?
        contract_start_date
      else
        nil
      end
    end

    # Override in including class if the principal field has a different name
    def principal_for_projection
      if respond_to?(:principal_amount) && principal_amount.present?
        principal_amount
      elsif respond_to?(:initial_balance) && initial_balance.present?
        initial_balance
      elsif account&.respond_to?(:first_valuation_amount)
        account.first_valuation_amount
      else
        nil
      end
    end

    # Monthly compound interest: P * (1 + r/12)^n
    def calculate_monthly_compound(principal, months)
      return principal if interest_rate.nil? || interest_rate.zero?

      monthly_rate = interest_rate / 100.0 / 12.0
      principal * ((1 + monthly_rate) ** months)
    end

    # Daily compound interest: P * (1 + r/365)^n
    def calculate_daily_compound(principal, days)
      return principal if interest_rate.nil? || interest_rate.zero?

      daily_rate = interest_rate / 100.0 / 365.0
      principal * ((1 + daily_rate) ** days)
    end

    # Annual compound interest: P * (1 + r)^n
    def calculate_annual_compound(principal, years)
      return principal if interest_rate.nil? || interest_rate.zero?

      annual_rate = interest_rate / 100.0
      principal * ((1 + annual_rate) ** years)
    end
end
