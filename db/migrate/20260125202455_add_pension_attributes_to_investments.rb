class AddPensionAttributesToInvestments < ActiveRecord::Migration[7.2]
  def change
    add_column :investments, :can_cash_out_early, :boolean, default: false
    add_column :investments, :has_surrender_value, :boolean, default: false
    add_column :investments, :surrender_value, :decimal, precision: 19, scale: 4
  end
end
