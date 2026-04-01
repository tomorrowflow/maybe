class AddPersonSupportToRetirementScenarios < ActiveRecord::Migration[7.2]
  def change
    add_column :retirement_scenarios, :scenario_type, :string, default: "household"
    add_reference :retirement_scenarios, :person, type: :uuid, foreign_key: { to_table: :persons }, null: true

    create_table :retirement_scenario_persons, id: :uuid do |t|
      t.references :retirement_scenario, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.references :person, null: false, foreign_key: { to_table: :persons, on_delete: :cascade }, type: :uuid

      # Per-person income & retirement fields
      t.decimal :current_annual_salary, precision: 10, scale: 2
      t.date :salary_end_date
      t.integer :retirement_age
      t.date :target_retirement_date

      # Per-person state pension
      t.date :state_pension_start_date
      t.decimal :state_pension_monthly, precision: 10, scale: 2

      # Post-retirement income (part-time work)
      t.decimal :post_retirement_income_monthly, precision: 10, scale: 2
      t.date :post_retirement_income_start_date
      t.date :post_retirement_income_end_date

      t.timestamps
    end

    add_index :retirement_scenario_persons,
              [ :retirement_scenario_id, :person_id ],
              unique: true,
              name: "idx_retirement_scenario_persons_unique"
  end
end
