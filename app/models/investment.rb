class Investment < ApplicationRecord
  include Accountable

  SUBTYPES = {
    "brokerage" => { short: "Brokerage", long: "Brokerage" },
    "pension" => { short: "Pension", long: "Pension" },
    "retirement" => { short: "Retirement", long: "Retirement" },
    "401k" => { short: "401(k)", long: "401(k)" },
    "roth_401k" => { short: "Roth 401(k)", long: "Roth 401(k)" },
    "529_plan" => { short: "529 Plan", long: "529 Plan" },
    "hsa" => { short: "HSA", long: "Health Savings Account" },
    "mutual_fund" => { short: "Mutual Fund", long: "Mutual Fund" },
    "ira" => { short: "IRA", long: "Traditional IRA" },
    "roth_ira" => { short: "Roth IRA", long: "Roth IRA" },
    "angel" => { short: "Angel", long: "Angel" },
    "riester" => { short: "Riester", long: "Riester Pension (Riester-Rente)" },
    "ruerup" => { short: "Rürup", long: "Rürup Pension (Basisrente)" },
    "betriebsrente" => { short: "Betriebsrente", long: "Occupational Pension (Betriebliche Altersvorsorge)" }
  }.freeze

  GERMAN_PENSION_SUBTYPES = %w[riester ruerup betriebsrente].freeze

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
end
