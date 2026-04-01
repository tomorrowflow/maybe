class AddLocalePreferencesToFamilies < ActiveRecord::Migration[7.2]
  def change
    add_column :families, :number_format, :string, default: "1,234.56"
    add_column :families, :measurement_system, :string, default: "metric"
  end
end
