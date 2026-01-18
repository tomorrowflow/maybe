class AddPensionFieldsToInvestments < ActiveRecord::Migration[7.2]
  def change
    add_column :investments, :retirement_date, :date
    add_column :investments, :expected_monthly_payout, :decimal, precision: 10, scale: 2
  end
end
