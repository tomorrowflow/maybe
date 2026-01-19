class RetirementScenario
  class SnapshotHistoryBuilder
    attr_reader :scenario

    def initialize(scenario)
      @scenario = scenario
    end

    # Build chart data for D3.js line visualization
    def build_chart_data
      snapshots = scenario.snapshots.chronological.to_a

      return empty_chart_data if snapshots.empty?

      {
        series: build_series_data(snapshots),
        current_point: build_current_point,
        metadata: build_metadata(snapshots)
      }
    end

    # JSON-ready format for frontend
    def to_json_chart_data
      build_chart_data.to_json
    end

    private

      def empty_chart_data
        {
          series: { actual: [], projected: [], required: [] },
          current_point: nil,
          metadata: {
            currency: scenario.family.currency,
            currency_symbol: Money::Currency.new(scenario.family.currency).symbol,
            has_data: false,
            snapshot_count: 0
          }
        }
      end

      def build_series_data(snapshots)
        actual_data = []
        projected_data = []
        required_data = []

        snapshots.each do |snapshot|
          date_str = snapshot.snapshot_date.to_s

          actual_data << {
            date: date_str,
            value: snapshot.current_portfolio_value.to_f.round(2),
            progress_percent: snapshot.progress_percent.to_f.round(1)
          }

          if snapshot.projected_portfolio_value.present?
            projected_data << {
              date: date_str,
              value: snapshot.projected_portfolio_value.to_f.round(2)
            }
          end

          required_data << {
            date: date_str,
            value: snapshot.required_portfolio_value.to_f.round(2)
          }
        end

        {
          actual: actual_data,
          projected: projected_data,
          required: required_data
        }
      end

      def build_current_point
        # Add current state as the latest point (if different from last snapshot)
        latest_snapshot = scenario.latest_snapshot
        return nil unless latest_snapshot
        return nil if latest_snapshot.snapshot_date == Date.today

        {
          date: Date.today.to_s,
          actual_value: scenario.current_portfolio_value.to_f.round(2),
          projected_value: scenario.calculate_projected_portfolio_for_today&.round(2),
          required_value: scenario.required_portfolio_value.to_f.round(2),
          progress_percent: scenario.progress_percent.round(1)
        }
      end

      def build_metadata(snapshots)
        first_snapshot = snapshots.first
        latest_snapshot = snapshots.last
        accuracy = scenario.assumption_accuracy_summary

        {
          currency: scenario.family.currency,
          currency_symbol: Money::Currency.new(scenario.family.currency).symbol,
          has_data: true,
          snapshot_count: snapshots.count,
          first_snapshot_date: first_snapshot.snapshot_date.to_s,
          latest_snapshot_date: latest_snapshot.snapshot_date.to_s,
          tracking_status: latest_snapshot.tracking_status.to_s,
          tracking_status_label: latest_snapshot.tracking_status_label,
          portfolio_variance: latest_snapshot.portfolio_variance&.round(2),
          portfolio_variance_percent: latest_snapshot.portfolio_variance_percent,
          assumed_growth_rate: accuracy&.dig(:assumed_growth_rate),
          actual_growth_rate: accuracy&.dig(:actual_growth_rate),
          growth_rate_variance: accuracy&.dig(:growth_rate_variance)
        }
      end
  end
end
