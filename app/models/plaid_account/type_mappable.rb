module PlaidAccount::TypeMappable
  extend ActiveSupport::Concern

  UnknownAccountTypeError = Class.new(StandardError)

  def map_accountable(plaid_type)
    accountable_class = TYPE_MAPPING.dig(
      plaid_type.to_sym,
      :accountable
    )

    unless accountable_class
      raise UnknownAccountTypeError, "Unknown account type: #{plaid_type}"
    end

    accountable_class.new
  end

  def map_subtype(plaid_type, plaid_subtype)
    TYPE_MAPPING.dig(
      plaid_type.to_sym,
      :subtype_mapping,
      plaid_subtype
    ) || "other"
  end

  # Plaid Account Types -> Accountable Types
  # https://plaid.com/docs/api/accounts/#account-type-schema
  TYPE_MAPPING = {
    depository: {
      accountable: Depository,
      subtype_mapping: {
        "checking" => "checking",
        "savings" => "savings",
        "hsa" => "savings",           # Map US HSA to Savings (European version)
        "cd" => "fixed_deposit",      # Map US CD to Fixed Deposit
        "money market" => "call_money" # Map US Money Market to Call Money
      }
    },
    credit: {
      accountable: CreditCard,
      subtype_mapping: {
        "credit card" => "credit_card"
      }
    },
    loan: {
      accountable: Loan,
      subtype_mapping: {
        "mortgage" => "mortgage",
        "student" => "student",
        "auto" => "auto",
        "business" => "business",
        "home equity" => "home_equity",
        "line of credit" => "line_of_credit"
      }
    },
    investment: {
      accountable: Investment,
      subtype_mapping: {
        "brokerage" => "brokerage",
        "pension" => "pension",
        "retirement" => "retirement",
        "401k" => "retirement",      # Map US 401k to generic Retirement (European version)
        "roth 401k" => "retirement", # Map US Roth 401k to generic Retirement
        "529" => "brokerage",        # Map US 529 to Brokerage
        "hsa" => "brokerage",        # Map US HSA to Brokerage
        "mutual fund" => "mutual_fund",
        "roth" => "retirement",      # Map US Roth IRA to generic Retirement
        "ira" => "retirement"        # Map US IRA to generic Retirement
      }
    },
    other: {
      accountable: OtherAsset,
      subtype_mapping: {}
    }
  }
end
