class Insurance < ApplicationRecord
  include Accountable

  SUBTYPES = {
    "kapitallebensversicherung" => { short: "Kapitallebensversicherung", long: "Endowment Life Insurance (Kapitallebensversicherung)" },
    "berufsunfaehigkeit" => { short: "Berufsunfähigkeit", long: "Disability Insurance (Berufsunfähigkeitsversicherung)" },
    "other" => { short: "Other", long: "Other Insurance" }
  }.freeze

  PREMIUM_FREQUENCIES = %w[monthly quarterly semi_annual annual].freeze

  validates :premium_frequency, inclusion: { in: PREMIUM_FREQUENCIES }, allow_nil: true

  class << self
    def icon
      "shield"
    end

    def color
      "#7C3AED"
    end

    def classification
      "asset"
    end
  end

  def annual_premium
    return nil unless premium_amount && premium_frequency

    multiplier = case premium_frequency
    when "monthly" then 12
    when "quarterly" then 4
    when "semi_annual" then 2
    when "annual" then 1
    else 1
    end

    Money.new(premium_amount * multiplier, account.currency)
  end

  def years_until_maturity
    return nil unless maturity_date
    ((maturity_date - Date.today).to_f / 365.25).ceil
  end

  def cash_value
    Money.new(cash_surrender_value || 0, account.currency)
  end
end
