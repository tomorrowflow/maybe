class AddExpectedGrowthRateToInvestments < ActiveRecord::Migration[7.2]
  def change
    add_column :investments, :expected_growth_rate, :decimal, precision: 10, scale: 3
  end
end
