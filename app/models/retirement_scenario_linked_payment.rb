class RetirementScenarioLinkedPayment < ApplicationRecord
  include Monetizable

  belongs_to :retirement_scenario
  belongs_to :account, optional: true

  monetize :monthly_amount

  validates :transaction_name, presence: true
  validates :transaction_name, uniqueness: { scope: :retirement_scenario_id }

  scope :linked_to_account, -> { where.not(account_id: nil).where(is_regular_expense: false) }
  scope :regular_expenses, -> { where(is_regular_expense: true) }

  def linked?
    account_id.present? && !is_regular_expense?
  end

  private

    def monetizable_currency
      retirement_scenario&.family&.currency
    end
end
