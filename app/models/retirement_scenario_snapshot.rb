class RetirementScenarioSnapshot < ApplicationRecord
  include Monetizable

  belongs_to :retirement_scenario

  validates :snapshot_date, presence: true
  validates :snapshot_date, uniqueness: { scope: :retirement_scenario_id }

  monetize :current_portfolio_value,
           :required_portfolio_value,
           :portfolio_gap,
           :total_pension_income,
           :income_gap_monthly,
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

  # Variance as a percentage of projected
  def portfolio_variance_percent
    return nil unless projected_portfolio_value.present? && projected_portfolio_value > 0
    return nil unless portfolio_variance
    (portfolio_variance / projected_portfolio_value * 100).round(2)
  end

  # Is actual ahead of, behind, or on track with projection?
  def tracking_status
    return :no_projection unless projected_portfolio_value.present?

    variance_pct = portfolio_variance_percent
    return :on_track if variance_pct.nil?

    if variance_pct > 5
      :ahead
    elsif variance_pct < -5
      :behind
    else
      :on_track
    end
  end

  def tracking_status_label
    case tracking_status
    when :ahead then "Ahead of projection"
    when :behind then "Behind projection"
    when :on_track then "On track"
    else "No projection data"
    end
  end

  # Calculate actual growth rate since previous snapshot
  def actual_growth_rate_since(previous_snapshot)
    return nil unless previous_snapshot
    return nil unless current_portfolio_value.present? && previous_snapshot.current_portfolio_value.present?
    return nil if previous_snapshot.current_portfolio_value <= 0

    months = months_between(previous_snapshot.snapshot_date, snapshot_date)
    return nil if months <= 0

    # Calculate monthly growth rate, then annualize
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
