class BausparContract < ApplicationRecord
  include Accountable

  PHASES = %w[saving allocated loan closed].freeze

  validates :bausparsumme, presence: true, numericality: { greater_than: 0 }
  validates :phase, presence: true, inclusion: { in: PHASES }
  validates :minimum_savings_percent, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :minimum_savings_period_months, numericality: { greater_than: 0 }, allow_nil: true
  validates :monthly_contribution, numericality: { greater_than: 0 }, allow_nil: true

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
    "Building Savings"
  end

  # Phase predicates
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

  # Calculate savings progress toward the minimum savings threshold
  def savings_progress_percent
    return 0 unless bausparsumme && bausparsumme > 0

    current_balance = account.balance_money.amount
    target = bausparsumme * (savings_target_percent / 100.0)

    [ (current_balance / target * 100).round(1), 100 ].min
  end

  # The savings target percentage (default 40%, can vary by tariff)
  def savings_target_percent
    minimum_savings_percent || 40.0
  end

  # Target savings amount (typically 40-50% of Bausparsumme)
  def savings_target_amount
    Money.new(bausparsumme * (savings_target_percent / 100.0), account.currency)
  end

  # Available loan amount after savings phase
  def available_loan_amount
    return nil unless bausparsumme
    current_balance = account.balance_money.amount
    Money.new([ bausparsumme - current_balance, 0 ].max, account.currency)
  end

  # Check if minimum savings period has been met
  def minimum_savings_period_met?
    return true unless contract_start_date && minimum_savings_period_months

    months_elapsed = ((Date.current - contract_start_date) / 30.44).floor
    months_elapsed >= minimum_savings_period_months
  end

  # Months remaining until minimum savings period is met
  def months_until_minimum_period
    return 0 unless contract_start_date && minimum_savings_period_months

    months_elapsed = ((Date.current - contract_start_date) / 30.44).floor
    remaining = minimum_savings_period_months - months_elapsed
    [ remaining, 0 ].max
  end

  # Check if Bewertungszahl requirement is met
  def bewertungszahl_met?
    return true unless minimum_bewertungszahl && current_bewertungszahl

    current_bewertungszahl >= minimum_bewertungszahl
  end

  # Check if all allocation requirements are met
  def allocation_ready?
    return false unless saving_phase?

    savings_progress_percent >= 100 &&
      minimum_savings_period_met? &&
      bewertungszahl_met?
  end

  # Estimated monthly payment based on standard 3-4‰ of Bausparsumme
  def suggested_monthly_contribution
    return nil unless bausparsumme
    Money.new(bausparsumme * 0.004, account.currency) # 4‰ default
  end

  # Years until expected allocation
  def years_until_allocation
    return nil unless expected_allocation_date
    return 0 if expected_allocation_date <= Date.current

    ((expected_allocation_date - Date.current) / 365.25).round(1)
  end

  # Contract duration in years
  def contract_duration_years
    return nil unless contract_start_date

    ((Date.current - contract_start_date) / 365.25).round(1)
  end

  # Check if any state subsidies are available
  def has_subsidies?
    wohnungsbauspraemie_eligible? ||
      arbeitnehmersparzulage_eligible? ||
      wohn_riester_eligible? ||
      vermoegenswirksame_leistungen?
  end

  # List of active subsidies
  def active_subsidies
    subsidies = []
    subsidies << "Wohnungsbauprämie" if wohnungsbauspraemie_eligible?
    subsidies << "Arbeitnehmersparzulage" if arbeitnehmersparzulage_eligible?
    subsidies << "Wohn-Riester" if wohn_riester_eligible?
    subsidies << "Vermögenswirksame Leistungen" if vermoegenswirksame_leistungen?
    subsidies
  end
end
