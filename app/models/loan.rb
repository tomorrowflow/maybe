class Loan < ApplicationRecord
  include Accountable

  SUBTYPES = {
    "mortgage" => { short: "Mortgage", long: "Mortgage" },
    "student" => { short: "Student", long: "Student Loan" },
    "auto" => { short: "Auto", long: "Auto Loan" },
    "bauspardarlehen" => { short: "Bauspardarlehen", long: "Building Savings Loan (Bauspardarlehen)" },
    "kfw" => { short: "KfW", long: "KfW Loan" },
    "other" => { short: "Other", long: "Other Loan" }
  }.freeze

  validates :effective_interest_rate, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :extra_payment_allowance_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validate :maturity_date_in_future, if: :maturity_date
  validate :fixed_rate_end_date_in_future, if: :fixed_rate_end_date

  def monthly_payment
    return nil if term_months.nil? || interest_rate.nil? || rate_type.nil? || rate_type != "fixed"
    return Money.new(0, account.currency) if account.loan.original_balance.amount.zero? || term_months.zero?

    annual_rate = interest_rate / 100.0
    monthly_rate = annual_rate / 12.0

    if monthly_rate.zero?
      payment = account.loan.original_balance.amount / term_months
    else
      payment = (account.loan.original_balance.amount * monthly_rate * (1 + monthly_rate)**term_months) / ((1 + monthly_rate)**term_months - 1)
    end

    Money.new(payment.round, account.currency)
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
