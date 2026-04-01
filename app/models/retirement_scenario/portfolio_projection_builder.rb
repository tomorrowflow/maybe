class RetirementScenario
  class PortfolioProjectionBuilder
    attr_reader :scenario

    def initialize(scenario)
      @scenario = scenario
    end

    # Build chart data from cached Monte Carlo results
    def build_chart_data
      results = scenario.monte_carlo_results
      return empty_chart_data unless results.present? && results["percentiles"].present?

      years = results["years"] || []
      percentiles = results["percentiles"] || {}
      start_date = scenario.calculation_date || Date.today

      {
        confidence_bands: build_confidence_bands(years, percentiles, start_date),
        median_line: build_median_line(years, percentiles, start_date),
        metadata: build_metadata(results, years)
      }
    end

    def to_json_chart_data
      build_chart_data.to_json
    end

    private

      def build_confidence_bands(years, percentiles, start_date)
        return [] unless percentiles["p10"] && percentiles["p90"]

        years.map.with_index do |year, i|
          date = (start_date + year.years).to_s
          {
            date: date,
            year: year,
            p10: (percentiles["p10"][i] || 0).round(2),
            p25: (percentiles["p25"][i] || 0).round(2),
            p50: (percentiles["p50"][i] || 0).round(2),
            p75: (percentiles["p75"][i] || 0).round(2),
            p90: (percentiles["p90"][i] || 0).round(2)
          }
        end
      end

      def build_median_line(years, percentiles, start_date)
        return [] unless percentiles["p50"]

        years.map.with_index do |year, i|
          {
            date: (start_date + year.years).to_s,
            value: (percentiles["p50"][i] || 0).round(2)
          }
        end
      end

      def build_metadata(results, years)
        {
          currency: scenario.family.currency,
          success_rate: results["success_rate"],
          simulation_count: results["simulation_count"],
          projection_years: years.size - 1,
          starting_value: scenario.current_portfolio_value&.to_f&.round(2),
          median_final_value: results.dig("percentiles", "p50")&.last&.round(2),
          worst_case_final_value: results.dig("percentiles", "p10")&.last&.round(2),
          best_case_final_value: results.dig("percentiles", "p90")&.last&.round(2),
          median_depletion_year: results["median_depletion_year"],
          worst_case_depletion_year: results["worst_case_depletion_year"],
          growth_rate: scenario.portfolio_growth_rate,
          growth_std_dev: scenario.portfolio_growth_std_dev,
          inflation_rate: scenario.inflation_rate
        }
      end

      def empty_chart_data
        {
          confidence_bands: [],
          median_line: [],
          metadata: {
            currency: scenario.family.currency,
            success_rate: nil,
            simulation_count: 0,
            projection_years: 0,
            starting_value: scenario.current_portfolio_value&.to_f
          }
        }
      end
  end
end
