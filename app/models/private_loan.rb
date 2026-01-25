class PrivateLoan < ApplicationRecord
  include Accountable

  RATE_TYPES = %w[fixed variable].freeze
  REPAYMENT_TYPES = %w[annuity bullet interest_only custom].freeze

  validates :principal_amount, presence: true, numericality: { greater_than: 0 }
  validates :rate_type, inclusion: { in: RATE_TYPES }, allow_nil: true
  validates :repayment_type, inclusion: { in: REPAYMENT_TYPES }, allow_nil: true
  validates :interest_rate, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :term_months, numericality: { greater_than: 0 }, allow_nil: true

  class << self
    def icon
      "hand-coins"
    end

    def color
      "#8B5CF6" # Purple for lending
    end

    def classification
      "asset"
    end
  end

  def display_name
    "Private Loan"
  end

  # Calculate monthly payment for annuity loans
  def monthly_payment
    return nil unless principal_amount && interest_rate && term_months
    return nil if term_months <= 0

    case repayment_type
    when "bullet"
      # Interest only during term, principal at end
      monthly_interest_payment
    when "interest_only"
      monthly_interest_payment
    when "annuity"
      calculate_annuity_payment
    else
      nil
    end
  end

  def monthly_payment_money
    return nil unless monthly_payment
    Money.new(monthly_payment, account.currency)
  end

  # Monthly interest payment
  def monthly_interest_payment
    return nil unless principal_amount && interest_rate
    return 0 if interest_rate <= 0

    monthly_rate = interest_rate / 100.0 / 12
    principal_amount * monthly_rate
  end

  def monthly_interest_money
    return nil unless monthly_interest_payment
    Money.new(monthly_interest_payment, account.currency)
  end

  # Total interest over the life of the loan
  def total_interest
    return nil unless principal_amount && interest_rate && term_months

    case repayment_type
    when "bullet", "interest_only"
      monthly_interest_payment * term_months
    when "annuity"
      return nil unless monthly_payment
      (monthly_payment * term_months) - principal_amount
    else
      nil
    end
  end

  def total_interest_money
    return nil unless total_interest
    Money.new(total_interest, account.currency)
  end

  # Total amount to be repaid (principal + interest)
  def total_repayment
    return nil unless principal_amount && total_interest
    principal_amount + total_interest
  end

  def total_repayment_money
    return nil unless total_repayment
    Money.new(total_repayment, account.currency)
  end

  # Principal amount as Money
  def principal_money
    return nil unless principal_amount
    Money.new(principal_amount, account.currency)
  end

  # Outstanding balance (current account balance represents what's still owed to you)
  def outstanding_balance
    account.balance_money
  end

  # Percentage of principal that has been repaid
  def repayment_progress_percent
    return 0 unless principal_amount && principal_amount > 0

    repaid = principal_amount - account.balance
    [ (repaid / principal_amount * 100).round(1), 100 ].min
  end

  # Check if loan is past due
  def past_due?
    return false unless maturity_date
    maturity_date < Date.current && account.balance > 0
  end

  # Days until maturity
  def days_until_maturity
    return nil unless maturity_date
    return 0 if maturity_date <= Date.current

    (maturity_date - Date.current).to_i
  end

  # Months until maturity
  def months_until_maturity
    return nil unless maturity_date
    return 0 if maturity_date <= Date.current

    ((maturity_date - Date.current) / 30.44).round(1)
  end

  # Loan duration in months (from start to now or maturity)
  def elapsed_months
    return nil unless start_date

    end_date = [ maturity_date, Date.current ].compact.min
    ((end_date - start_date) / 30.44).round(1)
  end

  # Repayment type description
  def repayment_type_description
    case repayment_type
    when "annuity"
      "Annuity (Equal Payments)"
    when "bullet"
      "Bullet (Interest Only, Principal at End)"
    when "interest_only"
      "Interest Only"
    when "custom"
      "Custom Schedule"
    else
      "Not Specified"
    end
  end

  # Rate type description
  def rate_type_description
    case rate_type
    when "fixed"
      "Fixed Rate"
    when "variable"
      "Variable Rate"
    else
      "Not Specified"
    end
  end

  private

  def calculate_annuity_payment
    return nil unless interest_rate && interest_rate > 0 && term_months && term_months > 0

    monthly_rate = interest_rate / 100.0 / 12
    # PMT formula: P * (r * (1 + r)^n) / ((1 + r)^n - 1)
    numerator = monthly_rate * ((1 + monthly_rate) ** term_months)
    denominator = ((1 + monthly_rate) ** term_months) - 1

    principal_amount * (numerator / denominator)
  end
end
