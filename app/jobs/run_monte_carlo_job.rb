class RunMonteCarloJob < ApplicationJob
  queue_as :default

  def perform(scenario_id)
    scenario = RetirementScenario.find_by(id: scenario_id)
    return unless scenario
    return if scenario.monte_carlo_running?

    scenario.run_monte_carlo!
    scenario.reload

    broadcast_results(scenario)
  rescue => e
    Rails.logger.error("RunMonteCarloJob failed for scenario #{scenario_id}: #{e.message}")
    Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
    scenario&.update_columns(monte_carlo_status: "failed") rescue nil
  end

  private

    def broadcast_results(scenario)
      Turbo::StreamsChannel.broadcast_replace_to(
        scenario.family,
        target: "monte-carlo-results-#{scenario.id}",
        partial: "retirement_scenarios/monte_carlo_card",
        locals: { scenario: scenario }
      )
    rescue => e
      Rails.logger.error("Monte Carlo broadcast failed: #{e.message}")
      Rails.logger.error(e.backtrace&.first(5)&.join("\n"))
    end
end
