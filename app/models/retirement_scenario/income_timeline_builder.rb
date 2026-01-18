class RetirementScenario
  class IncomeTimelineBuilder
    attr_reader :scenario

    def initialize(scenario)
      @scenario = scenario
    end

    # Build chart data for D3.js stacked area visualization
    def build_chart_data(years: 30)
      timeline = scenario.generate_income_timeline(years: years)

      {
        series: build_series_data(timeline),
        milestones: build_milestone_markers,
        gap_period: build_gap_period_data,
        expenses_line: build_expenses_line(timeline),
        metadata: build_metadata(years)
      }
    end

    # JSON-ready format for frontend
    def to_json_chart_data(years: 30)
      build_chart_data(years: years).to_json
    end

    private

      def build_series_data(timeline)
        # Each series is an array of [date, value] points
        {
          salary: timeline.map { |t| { date: t[:date].to_s, value: t[:salary].to_f.round(2) } },
          state_pension: timeline.map { |t| { date: t[:date].to_s, value: t[:state_pension].to_f.round(2) } },
          private_pensions: timeline.map { |t| { date: t[:date].to_s, value: t[:private_pensions].to_f.round(2) } },
          other: timeline.map { |t| { date: t[:date].to_s, value: t[:other].to_f.round(2) } }
        }
      end

      def build_milestone_markers
        scenario.income_milestones.map do |milestone|
          {
            date: milestone[:date].to_s,
            type: milestone[:type].to_s,
            label: milestone[:label],
            description: milestone[:description],
            amount: milestone[:amount]&.to_f&.round(2)
          }
        end
      end

      def build_gap_period_data
        gap = scenario.gap_period
        return nil unless gap

        {
          start_date: gap[:start_date].to_s,
          end_date: gap[:end_date].to_s,
          months: gap[:months],
          monthly_shortfall: gap[:monthly_shortfall].to_f.round(2),
          total_needed: scenario.gap_bridge_amount.to_f.round(2),
          can_bridge: scenario.can_bridge_gap?
        }
      end

      def build_expenses_line(timeline)
        timeline.map { |t| { date: t[:date].to_s, value: t[:expenses].to_f.round(2) } }
      end

      def build_metadata(years)
        {
          currency: scenario.family.currency,
          currency_symbol: Money::Currency.find(scenario.family.currency)&.symbol || "$",
          start_date: (scenario.calculation_date || Date.today).to_s,
          end_date: ((scenario.calculation_date || Date.today) + years.years).to_s,
          years: years,
          has_gap: scenario.gap_period.present?,
          income_today: scenario.income_at_today.to_f.round(2),
          income_at_retirement: scenario.income_at_retirement&.to_f&.round(2),
          income_at_full_pension: scenario.income_at_full_pension.to_f.round(2),
          monthly_expenses: scenario.retirement_monthly_expenses&.to_f&.round(2)
        }
      end
  end
end
