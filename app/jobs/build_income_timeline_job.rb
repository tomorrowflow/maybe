class BuildIncomeTimelineJob < ApplicationJob
  queue_as :default

  def perform(scenario_id)
    scenario = RetirementScenario.find_by(id: scenario_id)
    return unless scenario
    return if scenario.income_timeline_status == "running"

    scenario.update_columns(income_timeline_status: "running")

    builder = RetirementScenario::IncomeTimelineBuilder.new(scenario)
    results = builder.build_chart_data

    scenario.update_columns(
      income_timeline_results: results,
      income_timeline_status: "completed",
      income_timeline_ran_at: Time.current
    )

    scenario.reload
    broadcast_results(scenario)
  rescue => e
    Rails.logger.error("BuildIncomeTimelineJob failed for scenario #{scenario_id}: #{e.message}")
    Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
    scenario&.update_columns(income_timeline_status: "failed") rescue nil
  end

  private

    def broadcast_results(scenario)
      Turbo::StreamsChannel.broadcast_replace_to(
        scenario.family,
        target: "income-timeline-results-#{scenario.id}",
        partial: "retirement_scenarios/income_timeline_results",
        locals: { scenario: scenario, chart_data: scenario.parsed_income_timeline_results }
      )
    rescue => e
      Rails.logger.error("Income timeline broadcast failed: #{e.message}")
    end
end
