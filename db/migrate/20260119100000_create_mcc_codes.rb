class CreateMccCodes < ActiveRecord::Migration[7.2]
  def change
    create_table :mcc_codes, id: :uuid do |t|
      t.string :code, null: false, limit: 4
      t.string :description, null: false
      t.string :category_hint

      t.timestamps
    end

    add_index :mcc_codes, :code, unique: true
  end
end
