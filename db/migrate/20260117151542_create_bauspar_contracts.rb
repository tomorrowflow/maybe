class CreateBausparContracts < ActiveRecord::Migration[7.2]
  def change
    create_table :bauspar_contracts, id: :uuid do |t|
      t.decimal :bausparsumme, precision: 19, scale: 4, null: false
      t.string :provider
      t.string :contract_number
      t.string :phase, null: false, default: "saving"
      t.decimal :savings_interest_rate, precision: 10, scale: 3
      t.decimal :loan_interest_rate, precision: 10, scale: 3

      t.jsonb :locked_attributes, default: {}
      t.timestamps
    end

    add_index :bauspar_contracts, :phase
  end
end
