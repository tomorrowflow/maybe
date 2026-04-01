class AddSavingsPoolToRetirementScenarios < ActiveRecord::Migration[7.2]
  def change
    add_column :retirement_scenarios, :current_savings_value, :decimal, precision: 19, scale: 4
    add_column :retirement_scenarios, :savings_overflow_threshold, :decimal, precision: 5, scale: 2, default: 2.0
  end
end
