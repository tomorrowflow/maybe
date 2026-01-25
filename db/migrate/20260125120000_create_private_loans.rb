class CreatePrivateLoans < ActiveRecord::Migration[7.2]
  def change
    create_table :private_loans, id: :uuid do |t|
      # Core loan details
      t.decimal :principal_amount, precision: 19, scale: 4, null: false
      t.decimal :interest_rate, precision: 10, scale: 4
      t.string :rate_type, default: "fixed" # fixed, variable
      t.integer :term_months

      # Repayment structure
      t.string :repayment_type, default: "annuity" # annuity, bullet, interest_only, custom

      # Timeline
      t.date :start_date
      t.date :maturity_date

      # Borrower information
      t.string :borrower_name
      t.text :borrower_notes

      # Contract details
      t.string :contract_number
      t.boolean :has_written_contract, default: false
      t.boolean :has_collateral, default: false
      t.string :collateral_description

      t.jsonb :locked_attributes, default: {}
      t.timestamps
    end

    add_index :private_loans, :maturity_date
    add_index :private_loans, :borrower_name
  end
end
