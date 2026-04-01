class Account < ApplicationRecord
  include AASM, Syncable, Monetizable, Chartable, Linkable, Enrichable, Anchorable, Reconcileable

  validates :name, :balance, :currency, presence: true

  belongs_to :family
  belongs_to :import, optional: true

  has_many :account_persons, dependent: :destroy
  has_many :persons, through: :account_persons

  has_many :import_mappings, as: :mappable, dependent: :destroy, class_name: "Import::Mapping"
  has_many :entries, dependent: :destroy
  has_many :transactions, through: :entries, source: :entryable, source_type: "Transaction"
  has_many :valuations, through: :entries, source: :entryable, source_type: "Valuation"
  has_many :trades, through: :entries, source: :entryable, source_type: "Trade"
  has_many :holdings, dependent: :destroy
  has_many :balances, dependent: :destroy
  has_many :retirement_scenario_pension_sources, class_name: "RetirementScenarioPensionSource", dependent: :destroy

  monetize :balance, :cash_balance

  enum :classification, { asset: "asset", liability: "liability" }, validate: { allow_nil: true }
  enum :ownership_type, { personal: "personal", joint: "joint", household: "household" }, default: :household

  scope :visible, -> { where(status: [ "draft", "active" ]) }
  scope :assets, -> { where(classification: "asset") }
  scope :liabilities, -> { where(classification: "liability") }
  scope :alphabetically, -> { order(:name) }
  scope :manual, -> { where(plaid_account_id: nil) }

  # Returns accounts visible to a specific person:
  # their personal accounts + joint accounts they're part of + all household accounts
  scope :for_person, ->(person) {
    left_joins(:account_persons)
      .where(
        "accounts.ownership_type = ? OR account_persons.person_id = ?",
        ownership_types[:household], person.id
      )
      .distinct
  }

  has_one_attached :logo

  delegated_type :accountable, types: Accountable::TYPES, dependent: :destroy

  accepts_nested_attributes_for :accountable, update_only: true

  # Account state machine
  aasm column: :status, timestamps: true do
    state :active, initial: true
    state :draft
    state :disabled
    state :pending_deletion

    event :activate do
      transitions from: [ :draft, :disabled ], to: :active
    end

    event :disable do
      transitions from: [ :draft, :active ], to: :disabled
    end

    event :enable do
      transitions from: :disabled, to: :active
    end

    event :mark_for_deletion do
      transitions from: [ :draft, :active, :disabled ], to: :pending_deletion
    end
  end

  class << self
    def create_and_sync(attributes)
      attributes[:accountable_attributes] ||= {} # Ensure accountable is created, even if empty
      account = new(attributes.merge(cash_balance: attributes[:balance]))
      initial_balance = attributes.dig(:accountable_attributes, :initial_balance)&.to_d

      transaction do
        account.save!

        manager = Account::OpeningBalanceManager.new(account)
        result = manager.set_opening_balance(balance: initial_balance || account.balance)
        raise result.error if result.error
      end

      account.sync_later
      account
    end
  end

  def institution_domain
    url_string = plaid_account&.plaid_item&.institution_url
    return nil unless url_string.present?

    begin
      uri = URI.parse(url_string)
      # Use safe navigation on .host before calling gsub
      uri.host&.gsub(/^www\./, "")
    rescue URI::InvalidURIError
      # Log a warning if the URL is invalid and return nil
      Rails.logger.warn("Invalid institution URL encountered for account #{id}: #{url_string}")
      nil
    end
  end

  def destroy_later
    mark_for_deletion!
    DestroyJob.perform_later(self)
  end

  # Override destroy to handle error recovery for accounts
  def destroy
    super
  rescue => e
    # If destruction fails, transition back to disabled state
    # This provides a cleaner recovery path than the generic scheduled_for_deletion flag
    disable! if may_disable?
    raise e
  end

  def current_holdings
    holdings.where(currency: currency)
            .where.not(qty: 0)
            .where(
              id: holdings.select("DISTINCT ON (security_id) id")
                          .where(currency: currency)
                          .order(:security_id, date: :desc)
            )
            .order(amount: :desc)
  end

  def start_date
    first_entry_date = entries.minimum(:date) || Date.current
    first_entry_date - 1.day
  end

  def lock_saved_attributes!
    super
    accountable.lock_saved_attributes!
  end

  def first_valuation
    entries.valuations.order(:date).first
  end

  def first_valuation_amount
    first_valuation&.amount_money || balance_money
  end

  # Get short version of the subtype label
  def short_subtype_label
    accountable_class.short_subtype_label_for(subtype) || accountable_class.display_name
  end

  # Get long version of the subtype label
  def long_subtype_label
    accountable_class.long_subtype_label_for(subtype) || accountable_class.display_name
  end

  # The balance type determines which "component" of balance is being tracked.
  # This is primarily used for balance related calculations and updates.
  #
  # "Cash" = "Liquid"
  # "Non-cash" = "Illiquid"
  # "Investment" = A mix of both, including brokerage cash (liquid) and holdings (illiquid)
  def balance_type
    case accountable_type
    when "Depository", "CreditCard"
      :cash
    when "Property", "Vehicle", "OtherAsset", "Loan", "OtherLiability", "PrivateLoan", "BausparContract", "Insurance"
      :non_cash
    when "Investment", "Crypto"
      :investment
    else
      raise "Unknown account type: #{accountable_type}"
    end
  end

  # Returns projected annual growth rate for this account (as percentage, e.g., 7.0 for 7%)
  # Used by retirement projections to calculate account-specific growth
  def projected_growth_rate(fallback_rate: nil)
    rate = case accountable_type
    when "BausparContract"
      accountable.savings_interest_rate
    when "Depository"
      accountable.interest_rate
    when "Investment", "Crypto", "OtherAsset"
      accountable.respond_to?(:expected_growth_rate) ? accountable.expected_growth_rate : nil
    when "Property"
      accountable.regional_growth_rate  # Try Eurostat HPI, falls back to nil
    when "Vehicle"
      nil  # No appreciation assumption for vehicles
    when "Loan", "CreditCard", "OtherLiability", "PrivateLoan"
      accountable.respond_to?(:interest_rate) ? accountable.interest_rate : nil
    else
      nil
    end
    rate || fallback_rate
  end

  # Returns the start/acquisition date for this account
  # Used for historical projections and interest calculations
  def account_start_date
    case accountable_type
    when "PrivateLoan", "Loan", "OtherLiability", "Insurance"
      accountable.respond_to?(:start_date) ? accountable.start_date : nil
    when "Depository", "Investment", "CreditCard"
      accountable.respond_to?(:opening_date) ? accountable.opening_date : nil
    when "Property", "Vehicle"
      accountable.respond_to?(:purchase_date) ? accountable.purchase_date : nil
    when "OtherAsset", "Crypto"
      accountable.respond_to?(:acquisition_date) ? accountable.acquisition_date : nil
    when "BausparContract"
      accountable.contract_start_date
    else
      nil
    end
  end
end
