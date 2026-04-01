class AddAccountOwnership < ActiveRecord::Migration[7.2]
  def change
    add_column :accounts, :ownership_type, :string, default: "household"
    add_index :accounts, :ownership_type

    create_table :account_persons, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :person, null: false, foreign_key: { to_table: :persons }, type: :uuid

      t.timestamps
    end

    add_index :account_persons, [ :account_id, :person_id ], unique: true
  end
end
