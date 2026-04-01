class Loan < ApplicationRecord
  include Accountable
  include InterestProjectable

  SUBTYPES = {
    "mortgage" => { short: "Mortgage", long: "Mortgage" },
    "student" => { short: "Student", long: "Student Loan" },
    "auto" => { short: "Auto", long: "Auto Loan" },
    "building_savings" => { short: "Building Savings", long: "Building Savings Loan" },
    "kfw" => { short: "KfW", long: "KfW Loan" },
    "personal" => { short: "Personal", long: "Personal Loan" },
    "other" => { short: "Other", long: "Other Loan" }
  }.freeze

  validates :effective_interest_rate, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :extra_payment_allowance_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validate :maturity_date_in_future, if: :maturity_date
  validate :fixed_rate_end_date_in_future, if: :fixed_rate_end_date

  def monthly_payment
    return nil if interest_rate.nil? || rate_type.nil? || rate_type != "fixed"
    return Money.new(0, account.currency) if account.loan.original_balance.amount.zero?

    if interest_only?
      # Interest-only: pay only interest each month, principal stays unchanged
      Money.new(monthly_interest_amount.round, account.currency)
    else
      # Annuity: pay principal + interest (standard amortization)
      return nil if term_months.nil? || term_months.zero?
      Money.new(annuity_payment_amount.round, account.currency)
    end
  end

  # Monthly interest amount (used for interest-only loans and display)
  def monthly_interest_amount
    return 0 if interest_rate.nil? || interest_rate.zero?
    annual_rate = interest_rate / 100.0
    account.loan.original_balance.amount * (annual_rate / 12.0)
  end

  def original_balance
    Money.new(account.first_valuation_amount, account.currency)
  end

  # Alias for existing interest_rate field (Sollzins)
  def sollzins
    interest_rate
  end

  # Effektivzins (APR)
  def effektivzins
    effective_interest_rate
  end

  # Days until fixed rate period ends
  def days_until_fixed_rate_end
    return nil unless fixed_rate_end_date
    (fixed_rate_end_date - Date.today).to_i
  end

  # Is fixed-rate period ending soon? (within 6 months)
  def fixed_rate_ending_soon?
    return false unless fixed_rate_end_date
    days = days_until_fixed_rate_end
    days.present? && days <= 180 && days > 0
  end

  private

    def annuity_payment_amount
      annual_rate = interest_rate / 100.0
      monthly_rate = annual_rate / 12.0

      if monthly_rate.zero?
        account.loan.original_balance.amount / term_months
      else
        (account.loan.original_balance.amount * monthly_rate * (1 + monthly_rate)**term_months) / ((1 + monthly_rate)**term_months - 1)
      end
    end

    def maturity_date_in_future
      errors.add(:maturity_date, "must be in the future") if maturity_date <= Date.today
    end

    def fixed_rate_end_date_in_future
      errors.add(:fixed_rate_end_date, "must be in the future") if fixed_rate_end_date <= Date.today
    end

    class << self
      def color
        "#D444F1"
      end

      def icon
        "hand-coins"
      end

      def classification
        "liability"
      end
    end
end
