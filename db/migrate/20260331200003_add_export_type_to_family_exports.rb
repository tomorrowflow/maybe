class AddExportTypeToFamilyExports < ActiveRecord::Migration[7.2]
  def change
    add_column :family_exports, :export_type, :string, default: "csv"
  end
end
