class AddLoanLinkToBausparContracts < ActiveRecord::Migration[7.2]
  def change
    add_reference :bauspar_contracts, :replaces_loan_account, type: :uuid,
                  foreign_key: { to_table: :accounts, on_delete: :nullify }, null: true
  end
end
