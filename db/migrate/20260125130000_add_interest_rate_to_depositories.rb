class AddInterestRateToDepositories < ActiveRecord::Migration[7.2]
  def change
    add_column :depositories, :interest_rate, :decimal, precision: 10, scale: 3
  end
end
