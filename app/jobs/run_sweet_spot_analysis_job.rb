class RunSweetSpotAnalysisJob < ApplicationJob
  queue_as :default

  def perform(scenario_id)
    scenario = RetirementScenario.find_by(id: scenario_id)
    return unless scenario
    return if scenario.sweet_spot_status == "running"

    scenario.update_columns(sweet_spot_status: "running")

    analyzer = RetirementScenario::SweetSpotAnalyzer.new(scenario)
    results = analyzer.analyze

    # Store as hash — JSONB column handles serialization
    scenario.update_columns(
      sweet_spot_results: results,
      sweet_spot_status: "completed",
      sweet_spot_ran_at: Time.current
    )

    # Reload to get the properly serialized data
    scenario.reload
    broadcast_results(scenario)
  rescue => e
    Rails.logger.error("RunSweetSpotAnalysisJob failed for scenario #{scenario_id}: #{e.message}")
    Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
    scenario&.update_columns(sweet_spot_status: "failed") rescue nil
  end

  private

    def broadcast_results(scenario)
      analysis = scenario.parsed_sweet_spot_results
      return unless analysis

      Turbo::StreamsChannel.broadcast_replace_to(
        scenario.family,
        target: "sweet-spot-results-#{scenario.id}",
        partial: "retirement_scenarios/sweet_spot_results",
        locals: { scenario: scenario, analysis: analysis }
      )
    rescue => e
      Rails.logger.error("Sweet spot broadcast failed: #{e.message}")
    end
end
