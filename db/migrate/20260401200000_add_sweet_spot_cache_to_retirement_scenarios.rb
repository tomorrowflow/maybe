class AddSweetSpotCacheToRetirementScenarios < ActiveRecord::Migration[7.2]
  def change
    add_column :retirement_scenarios, :sweet_spot_results, :jsonb, default: {}
    add_column :retirement_scenarios, :sweet_spot_status, :string, default: "pending"
    add_column :retirement_scenarios, :sweet_spot_ran_at, :datetime
  end
end
