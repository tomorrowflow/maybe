class AddAutoAiToImportMappings < ActiveRecord::Migration[7.2]
  def change
    add_column :import_mappings, :auto_ai, :boolean, default: false, null: false
  end
end
