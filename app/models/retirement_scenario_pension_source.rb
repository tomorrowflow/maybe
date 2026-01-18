class RetirementScenarioPensionSource < ApplicationRecord
  include Monetizable

  belongs_to :retirement_scenario
  belongs_to :account

  monetize :expected_monthly_payout

  validates :account_id, uniqueness: { scope: :retirement_scenario_id }
  validates :expected_monthly_payout, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # German pension account subtypes
  GERMAN_PENSION_SUBTYPES = %w[riester ruerup betriebsrente].freeze

  scope :with_payout, -> { where.not(expected_monthly_payout: [nil, 0]) }

  def pension_type_label
    account.short_subtype_label
  end

  def pension_type_key
    account.subtype
  end

  private

    def monetizable_currency
      retirement_scenario&.family&.currency
    end
end
