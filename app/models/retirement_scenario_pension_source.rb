class RetirementScenarioPensionSource < ApplicationRecord
  include Monetizable

  belongs_to :retirement_scenario
  belongs_to :account

  monetize :expected_monthly_payout

  validates :account_id, uniqueness: { scope: :retirement_scenario_id }
  validates :expected_monthly_payout, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Use the constant from Investment model
  GERMAN_PENSION_SUBTYPES = Investment::GERMAN_PENSION_SUBTYPES

  scope :with_payout, -> { where.not(expected_monthly_payout: [nil, 0]) }

  # Auto-populate from account's pension data if not already set
  def populate_from_account!
    return unless account&.accountable.is_a?(Investment)

    investment = account.accountable

    if expected_monthly_payout.blank? && investment.expected_monthly_payout.present?
      self.expected_monthly_payout = investment.expected_monthly_payout
    end

    if payout_start_date.blank? && investment.retirement_date.present?
      self.payout_start_date = investment.retirement_date
    end
  end

  # Check if values differ from account defaults
  def has_custom_values?
    return false unless account&.accountable.is_a?(Investment)

    investment = account.accountable

    (expected_monthly_payout.present? && expected_monthly_payout != investment.expected_monthly_payout) ||
      (payout_start_date.present? && payout_start_date != investment.retirement_date)
  end

  def pension_type_label
    account.short_subtype_label
  end

  def pension_type_key
    account.subtype
  end

  # Get the account's stored payout (for display)
  def account_expected_monthly_payout
    account&.accountable&.expected_monthly_payout
  end

  def account_retirement_date
    account&.accountable&.retirement_date
  end

  private

    def monetizable_currency
      retirement_scenario&.family&.currency
    end
end
