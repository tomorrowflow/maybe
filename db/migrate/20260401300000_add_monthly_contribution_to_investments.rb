class AddMonthlyContributionToInvestments < ActiveRecord::Migration[7.2]
  def change
    add_column :investments, :monthly_contribution, :decimal, precision: 19, scale: 4
  end
end
