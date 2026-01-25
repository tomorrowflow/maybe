class CreateCategoryKeywords < ActiveRecord::Migration[7.2]
  def change
    create_table :category_keywords, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :category, null: false, foreign_key: true, type: :uuid
      t.string :keyword, null: false
      t.string :match_type, null: false, default: "contains" # contains, starts_with, exact

      t.timestamps
    end

    add_index :category_keywords, [ :family_id, :keyword ], unique: true
  end
end
