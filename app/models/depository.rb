class Depository < ApplicationRecord
  include Accountable

  validates :interest_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true

  SUBTYPES = {
    "checking" => { short: "Checking", long: "Checking Account" },
    "savings" => { short: "Savings", long: "Savings Account" },
    "fixed_deposit" => { short: "Fixed Deposit", long: "Fixed-term Deposit" },
    "call_money" => { short: "Call Money", long: "Call Money Account" }
    # US-specific account types (commented out for European version)
    # "hsa" => { short: "HSA", long: "Health Savings Account" },
    # "cd" => { short: "CD", long: "Certificate of Deposit" },
    # "money_market" => { short: "MM", long: "Money Market" }
  }.freeze

  class << self
    def display_name
      "Cash"
    end

    def color
      "#875BF7"
    end

    def classification
      "asset"
    end

    def icon
      "landmark"
    end
  end
end
