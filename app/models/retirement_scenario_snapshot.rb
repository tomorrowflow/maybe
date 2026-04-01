class RetirementScenarioSnapshot < ApplicationRecord
  include Monetizable

  belongs_to :retirement_scenario

  validates :snapshot_date, presence: true
  validates :snapshot_date, uniqueness: { scope: :retirement_scenario_id }

  monetize :current_portfolio_value,
           :total_pension_income,
           :projected_portfolio_value,
           :monthly_contribution_assumption

  scope :chronological, -> { order(snapshot_date: :asc) }
  scope :reverse_chronological, -> { order(snapshot_date: :desc) }
  scope :recent, ->(limit = 5) { reverse_chronological.limit(limit) }

  # Variance between actual and projected portfolio value
  def portfolio_variance
    return nil unless projected_portfolio_value.present? && current_portfolio_value.present?
    current_portfolio_value - projected_portfolio_value
  end

  def portfolio_variance_money
    return nil unless portfolio_variance
    Money.new(portfolio_variance, currency)
  end

  def portfolio_variance_percent
    return nil unless projected_portfolio_value.present? && projected_portfolio_value > 0
    return nil unless portfolio_variance
    (portfolio_variance / projected_portfolio_value * 100).round(2)
  end

  # Tracking status based on Monte Carlo success rate changes
  def tracking_status
    return :no_data unless monte_carlo_success_rate.present?

    if monte_carlo_success_rate >= 80
      :on_track
    elsif monte_carlo_success_rate >= 50
      :needs_attention
    else
      :at_risk
    end
  end

  def tracking_status_label
    case tracking_status
    when :on_track then "On track"
    when :needs_attention then "Needs attention"
    when :at_risk then "At risk"
    else "No data"
    end
  end

  # Calculate actual growth rate since previous snapshot
  def actual_growth_rate_since(previous_snapshot)
    return nil unless previous_snapshot
    return nil unless current_portfolio_value.present? && previous_snapshot.current_portfolio_value.present?
    return nil if previous_snapshot.current_portfolio_value <= 0

    months = months_between(previous_snapshot.snapshot_date, snapshot_date)
    return nil if months <= 0

    total_growth = current_portfolio_value / previous_snapshot.current_portfolio_value
    monthly_rate = total_growth ** (1.0 / months) - 1
    annual_rate = ((1 + monthly_rate) ** 12 - 1) * 100

    annual_rate.round(2)
  end

  private

    def months_between(start_date, end_date)
      ((end_date.year - start_date.year) * 12) + (end_date.month - start_date.month)
    end

    def currency
      retirement_scenario.family.currency
    end

    def monetizable_currency
      currency
    end
end
