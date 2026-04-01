class RetirementScenario
  class Explorer
    QUICK_SIMULATION_COUNT = 200

    attr_reader :scenario, :params

    def initialize(scenario, params = {})
      @scenario = scenario
      @params = params.to_h.with_indifferent_access
    end

    # Run a quick Monte Carlo simulation with overridden parameters
    # Returns the results hash (not persisted)
    def explore
      engine = MonteCarloEngine.new(scenario, overrides: build_overrides)
      engine.run
    end

    private

      def build_overrides
        overrides = { simulation_count: QUICK_SIMULATION_COUNT }

        overrides[:retirement_monthly_expenses] = params[:retirement_monthly_expenses].to_f if params[:retirement_monthly_expenses].present?
        overrides[:monthly_contribution] = params[:monthly_contribution].to_f if params[:monthly_contribution].present?
        overrides[:portfolio_growth_rate] = params[:portfolio_growth_rate].to_f if params[:portfolio_growth_rate].present?
        overrides[:inflation_rate] = params[:inflation_rate].to_f if params[:inflation_rate].present?
        overrides[:target_age] = params[:target_age].to_i if params[:target_age].present?

        overrides.compact
      end
  end
end
