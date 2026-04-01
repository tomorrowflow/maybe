class AddIncomeTimelineCacheToRetirementScenarios < ActiveRecord::Migration[7.2]
  def change
    add_column :retirement_scenarios, :income_timeline_results, :jsonb, default: {}
    add_column :retirement_scenarios, :income_timeline_status, :string, default: "pending"
    add_column :retirement_scenarios, :income_timeline_ran_at, :datetime
  end
end
