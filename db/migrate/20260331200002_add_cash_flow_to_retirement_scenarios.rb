class AddCashFlowToRetirementScenarios < ActiveRecord::Migration[7.2]
  def change
    add_column :retirement_scenarios, :after_tax_monthly_income, :decimal, precision: 19, scale: 4
    add_column :retirement_scenarios, :monthly_living_expenses, :decimal, precision: 19, scale: 4

    create_table :retirement_scenario_milestones, id: :uuid do |t|
      t.references :retirement_scenario, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :milestone_type, null: false
      t.date :date, null: false
      t.string :label
      t.decimal :amount, precision: 19, scale: 4
      t.references :account, type: :uuid, foreign_key: { on_delete: :nullify }, null: true
      t.boolean :auto_detected, default: false

      t.timestamps
    end

    add_index :retirement_scenario_milestones, [ :retirement_scenario_id, :date ], name: "idx_milestones_scenario_date"
    add_index :retirement_scenario_milestones, :milestone_type
  end
end
