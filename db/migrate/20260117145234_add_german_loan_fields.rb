class AddGermanLoanFields < ActiveRecord::Migration[7.2]
  def change
    add_column :loans, :effective_interest_rate, :decimal, precision: 10, scale: 3
    add_column :loans, :fixed_rate_end_date, :date
    add_column :loans, :maturity_date, :date
    add_column :loans, :extra_payment_allowance_percent, :decimal, precision: 5, scale: 2

    add_index :loans, :fixed_rate_end_date
    add_index :loans, :maturity_date
  end
end
