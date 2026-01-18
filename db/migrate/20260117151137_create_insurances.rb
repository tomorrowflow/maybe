class CreateInsurances < ActiveRecord::Migration[7.2]
  def change
    create_table :insurances, id: :uuid do |t|
      t.string :provider
      t.string :policy_number
      t.decimal :premium_amount, precision: 10, scale: 2
      t.string :premium_frequency
      t.date :maturity_date
      t.decimal :cash_surrender_value, precision: 19, scale: 4

      t.jsonb :locked_attributes, default: {}
      t.timestamps
    end
  end
end
