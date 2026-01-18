class AddPortfolioGrowthToRetirementScenarios < ActiveRecord::Migration[7.2]
  def change
    add_column :retirement_scenarios, :portfolio_growth_rate, :decimal, precision: 5, scale: 2, default: 7.0
    add_column :retirement_scenarios, :monthly_contribution, :decimal, precision: 10, scale: 2
    add_column :retirement_scenarios, :inflation_rate, :decimal, precision: 5, scale: 2, default: 3.0
  end
end
