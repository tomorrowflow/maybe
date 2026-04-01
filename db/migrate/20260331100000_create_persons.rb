class CreatePersons < ActiveRecord::Migration[7.2]
  def change
    create_table :persons, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.string :first_name, null: false
      t.string :last_name
      t.date :date_of_birth
      t.integer :retirement_age
      t.string :gender
      t.string :country
      t.boolean :primary, default: false, null: false

      t.timestamps
    end

    add_index :persons, [ :family_id, :primary ]

    add_reference :users, :person, type: :uuid, foreign_key: { to_table: :persons }, null: true
  end
end
