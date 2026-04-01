class BausparContract < ApplicationRecord
  include Accountable

  belongs_to :replaces_loan_account, class_name: "Account", optional: true

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

  # Does this Bauspar replace a loan at allocation?
  def replaces_loan?
    replaces_loan_account.present?
  end

  # The loan amount when the Bauspar enters loan phase
  # = Bausparsumme minus saved amount (what you still need to borrow)
  # Returns a plain numeric value
  def available_loan_amount
    return 0 unless bausparsumme
    bs = bausparsumme.is_a?(Money) ? bausparsumme.amount.to_f : bausparsumme.to_f
    savings = account&.balance.to_f
    [ bs - savings, 0 ].max
  end

  # Monthly payment during the Bauspar loan phase
  # If loan_monthly_repayment is set (Tilgungsbeitrag), use it as the fixed repayment
  # and add the interest on top. Otherwise fall back to annuity calculation.
  # Returns a plain numeric value
  def bauspar_loan_monthly_payment
    # If fixed repayment is defined, total payment = repayment + interest on remaining balance
    # For simplicity, use the average interest over the loan term (interest on half the loan amount)
    if loan_monthly_repayment.present? && loan_monthly_repayment.to_f > 0
      loan_amount = available_loan_amount
      return 0 if loan_amount <= 0

      repayment = loan_monthly_repayment.to_f
      rate = (loan_interest_rate || 0).to_f / 100.0 / 12.0

      # Average monthly interest (decreases as principal is paid, so average = interest on half the loan)
      avg_monthly_interest = loan_amount * rate / 2.0
      return (repayment + avg_monthly_interest).round(2)
    end

    return nil unless loan_interest_rate.present? && loan_interest_rate.to_f > 0 && bausparsumme.present?

    loan_amount = available_loan_amount
    return 0 if loan_amount <= 0

    # Fallback: annuity calculation with estimated 10 year term
    estimated_term = 120

    rate = loan_interest_rate.to_f
    monthly_rate = rate / 100.0 / 12.0
    if monthly_rate.zero?
      loan_amount / estimated_term
    else
      (loan_amount * monthly_rate * (1 + monthly_rate)**estimated_term) / ((1 + monthly_rate)**estimated_term - 1)
    end
  end

  # Loan term in months, calculated from fixed repayment amount
  def bauspar_loan_term_months
    loan_amount = available_loan_amount
    return 120 if loan_amount <= 0 # default 10 years

    if loan_monthly_repayment.present? && loan_monthly_repayment.to_f > 0
      repayment = loan_monthly_repayment.to_f
      # Simple: term = loan / repayment (interest extends it slightly)
      rate = (loan_interest_rate || 0).to_f / 100.0 / 12.0
      if rate > 0
        # Iterative: simulate month by month
        balance = loan_amount
        months = 0
        while balance > 0 && months < 600 # cap at 50 years
          interest = balance * rate
          balance = balance + interest - repayment
          months += 1
          break if repayment <= interest # Would never pay off
        end
        months
      else
        (loan_amount / repayment).ceil
      end
    else
      120 # default 10 years
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

  # Available loan amount as Money (for display in views)
  def available_loan_amount_money
    Money.new(available_loan_amount, account.currency)
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
