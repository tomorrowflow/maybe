class AddCashflowAnalysisToRetirementScenarios < ActiveRecord::Migration[7.2]
  def change
    add_column :retirement_scenarios, :analysis_year, :integer

    create_table :retirement_scenario_linked_payments, id: :uuid do |t|
      t.references :retirement_scenario, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :transaction_name, null: false
      t.decimal :monthly_amount, precision: 19, scale: 4
      t.references :account, type: :uuid, foreign_key: { on_delete: :nullify }, null: true
      t.boolean :is_regular_expense, default: false

      t.timestamps
    end

    add_index :retirement_scenario_linked_payments,
              [ :retirement_scenario_id, :transaction_name ],
              unique: true,
              name: "idx_linked_payments_scenario_name"
  end
end
