class AddStartDateToInsurances < ActiveRecord::Migration[7.2]
  def change
    add_column :insurances, :start_date, :date unless column_exists?(:insurances, :start_date)
  end
end
