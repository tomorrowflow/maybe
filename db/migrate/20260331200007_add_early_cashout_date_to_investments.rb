class AddEarlyCashoutDateToInvestments < ActiveRecord::Migration[7.2]
  def change
    add_column :investments, :early_cashout_date, :date
  end
end
