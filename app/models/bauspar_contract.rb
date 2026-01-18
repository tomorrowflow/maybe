class BausparContract < ApplicationRecord
  include Accountable

  PHASES = %w[saving allocated loan closed].freeze

  validates :bausparsumme, presence: true, numericality: { greater_than: 0 }
  validates :phase, presence: true, inclusion: { in: PHASES }

  class << self
    def icon
      "piggy-bank"
    end

    def color
      "#10B981"
    end

    def classification
      "asset"
    end
  end

  def display_name
    "Building Savings (Bausparvertrag)"
  end

  # Phase display helpers
  def saving_phase?
    phase == "saving"
  end

  def allocated_phase?
    phase == "allocated"
  end

  def loan_phase?
    phase == "loan"
  end

  def closed_phase?
    phase == "closed"
  end

  # Calculate current status description
  def phase_description
    case phase
    when "saving"
      "Savings Phase (Ansparphase)"
    when "allocated"
      "Allocated - Ready for Loan (Zuteilung)"
    when "loan"
      "Loan Phase (Darlehensphase)"
    when "closed"
      "Closed"
    else
      "Unknown"
    end
  end

  # Savings target (typically 40-50% of Bausparsumme)
  # Using current balance from account for actual savings
  def savings_progress_percent
    return 0 unless bausparsumme && bausparsumme > 0
    current_balance = account.balance_money.amount
    target = bausparsumme * 0.4 # Default 40% target

    [ (current_balance / target * 100).round(1), 100 ].min
  end

  # Available loan amount after savings phase
  def available_loan_amount
    return nil unless bausparsumme
    current_balance = account.balance_money.amount
    Money.new([ bausparsumme - current_balance, 0 ].max, account.currency)
  end
end
