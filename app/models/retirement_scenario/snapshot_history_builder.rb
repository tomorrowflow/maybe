class RetirementScenario
  class SnapshotHistoryBuilder
    attr_reader :scenario

    def initialize(scenario)
      @scenario = scenario
    end

    def build_chart_data
      snapshots = scenario.snapshots.chronological.to_a
      return empty_chart_data if snapshots.empty?

      {
        series: {
          portfolio: snapshots.map { |s|
            {
              date: s.snapshot_date.to_s,
              value: s.current_portfolio_value&.to_f&.round(2),
              success_rate: s.monte_carlo_success_rate&.to_f
            }
          },
          projected: snapshots.filter_map { |s|
            next unless s.projected_portfolio_value.present?
            {
              date: s.snapshot_date.to_s,
              value: s.projected_portfolio_value.to_f.round(2)
            }
          }
        },
        metadata: {
          snapshot_count: snapshots.size,
          latest_tracking_status: snapshots.last&.tracking_status,
          latest_tracking_label: snapshots.last&.tracking_status_label,
          latest_success_rate: snapshots.last&.monte_carlo_success_rate&.to_f,
          portfolio_variance: snapshots.last&.portfolio_variance&.to_f&.round(2),
          portfolio_variance_percent: snapshots.last&.portfolio_variance_percent
        }
      }
    end

    def to_json_chart_data
      build_chart_data.to_json
    end

    private

      def empty_chart_data
        {
          series: { portfolio: [], projected: [] },
          metadata: { snapshot_count: 0 }
        }
      end
  end
end
