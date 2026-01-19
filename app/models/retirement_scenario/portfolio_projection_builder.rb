class RetirementScenario
  class PortfolioProjectionBuilder
    attr_reader :scenario

    def initialize(scenario)
      @scenario = scenario
    end

    # Build chart data for D3.js line/area visualization
    def build_chart_data(months: nil)
      months ||= calculate_projection_months
      projections = scenario.generate_projections(months: months)

      return empty_chart_data if projections.empty?

      {
        series: build_series_data(projections),
        milestones: build_milestone_markers(projections),
        required_portfolio: scenario.required_portfolio_value.to_f.round(2),
        metadata: build_metadata(projections, months)
      }
    end

    # JSON-ready format for frontend
    def to_json_chart_data(months: nil)
      build_chart_data(months: months).to_json
    end

    private

      def calculate_projection_months
        # Use months until retirement, clamped between 12 and 360 months
        base_months = scenario.months_until_retirement || 360
        [ [ base_months, 12 ].max, 360 ].min
      end

      def empty_chart_data
        {
          series: { portfolio: [], contributions: [], returns: [] },
          milestones: [],
          required_portfolio: 0,
          metadata: {
            currency: scenario.family.currency,
            currency_symbol: Money::Currency.new(scenario.family.currency).symbol,
            has_data: false
          }
        }
      end

      def build_series_data(projections)
        # Cumulative values for stacking
        cumulative_contributions = 0
        cumulative_returns = 0
        starting_value = scenario.current_portfolio_value.to_f

        portfolio_data = []
        contributions_data = []
        returns_data = []

        projections.each do |p|
          cumulative_contributions += p[:contribution].to_f
          cumulative_returns += p[:investment_return].to_f

          portfolio_data << {
            date: p[:date].to_s,
            value: p[:portfolio_value].to_f.round(2)
          }

          # These represent the composition of growth above starting value
          contributions_data << {
            date: p[:date].to_s,
            value: cumulative_contributions.round(2)
          }

          returns_data << {
            date: p[:date].to_s,
            value: cumulative_returns.round(2)
          }
        end

        {
          portfolio: portfolio_data,
          contributions: contributions_data,
          returns: returns_data,
          starting_value: starting_value.round(2)
        }
      end

      def build_milestone_markers(projections)
        milestones = []

        # Find retirement milestone (first month where can_retire becomes true)
        unless scenario.can_retire_now?
          retirement_projection = projections.find { |p| p[:can_retire] }
          if retirement_projection
            milestones << {
              date: retirement_projection[:date].to_s,
              type: "retirement_ready",
              label: "Retirement Ready",
              description: "Portfolio reaches required value",
              value: retirement_projection[:portfolio_value].to_f.round(2)
            }
          end
        end

        # Add yearly markers for context
        projections.each_with_index do |p, i|
          next unless i > 0 && i % 60 == 0 # Every 5 years
          milestones << {
            date: p[:date].to_s,
            type: "year_marker",
            label: "Year #{i / 12}",
            value: p[:portfolio_value].to_f.round(2)
          }
        end

        milestones
      end

      def build_metadata(projections, months)
        final_projection = projections.last
        first_retirement_month = projections.find_index { |p| p[:can_retire] }

        {
          currency: scenario.family.currency,
          currency_symbol: Money::Currency.new(scenario.family.currency).symbol,
          start_date: (scenario.calculation_date || Date.today).to_s,
          end_date: final_projection[:date].to_s,
          months: months,
          years: (months / 12.0).round(1),
          has_data: true,
          starting_value: scenario.current_portfolio_value.to_f.round(2),
          final_value: final_projection[:portfolio_value].to_f.round(2),
          total_contributions: scenario.total_contributions_projected(months).to_f.round(2),
          total_returns: scenario.total_returns_projected(months).to_f.round(2),
          required_portfolio: scenario.required_portfolio_value.to_f.round(2),
          can_retire_now: scenario.can_retire_now?,
          retirement_month: first_retirement_month,
          growth_rate: scenario.portfolio_growth_rate,
          inflation_rate: scenario.inflation_rate,
          real_growth_rate: scenario.real_portfolio_growth_rate,
          monthly_contribution: (scenario.monthly_contribution || scenario.median_monthly_surplus).to_f.round(2)
        }
      end
  end
end
