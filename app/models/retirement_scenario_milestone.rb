class RetirementScenarioMilestone < ApplicationRecord
  include Monetizable

  belongs_to :retirement_scenario
  belongs_to :account, optional: true

  monetize :amount

  MILESTONE_TYPES = %w[
    debt_payoff
    salary_change
    expense_change
    income_start
    income_stop
    bauspar_phase_change
    custom
  ].freeze

  enum :milestone_type, MILESTONE_TYPES.index_by(&:itself)

  validates :milestone_type, presence: true, inclusion: { in: MILESTONE_TYPES }
  validates :date, presence: true
  validates :label, presence: true

  scope :auto_detected, -> { where(auto_detected: true) }
  scope :user_added, -> { where(auto_detected: false) }
  scope :chronological, -> { order(:date) }
  scope :future, -> { where("date > ?", Date.current) }

  # Does this milestone free up cash flow? (debt payoff, income start)
  def frees_cash_flow?
    debt_payoff? || income_start?
  end

  # Does this milestone reduce cash flow? (income stop, expense change up)
  def reduces_cash_flow?
    income_stop?
  end

  # Monthly cash flow impact (positive = more savings, negative = less)
  def monthly_impact
    case milestone_type
    when "debt_payoff"
      amount || 0  # freed monthly payment
    when "salary_change"
      amount || 0  # new salary (absolute, not delta — caller must compute delta)
    when "expense_change"
      amount || 0  # new expense level (absolute)
    when "income_start"
      amount || 0  # new income stream
    when "income_stop"
      -(amount || 0)  # lost income
    when "bauspar_phase_change"
      amount || 0  # change in monthly payment
    else
      amount || 0
    end
  end

  def display_impact
    return nil unless amount.present?

    if frees_cash_flow?
      "+#{format_amount}/mo freed"
    elsif reduces_cash_flow?
      "-#{format_amount}/mo"
    else
      "#{format_amount}/mo"
    end
  end

  private

    def format_amount
      Money.new(amount.abs, retirement_scenario.family.currency).format
    end

    def monetizable_currency
      retirement_scenario&.family&.currency
    end
end
