class AddLoanRepaymentToBausparContracts < ActiveRecord::Migration[7.2]
  def change
    add_column :bauspar_contracts, :loan_monthly_repayment, :decimal, precision: 19, scale: 4
  end
end
