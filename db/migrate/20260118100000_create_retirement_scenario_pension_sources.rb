class CreateRetirementScenarioPensionSources < ActiveRecord::Migration[7.2]
  def change
    create_table :retirement_scenario_pension_sources, id: :uuid do |t|
      t.references :retirement_scenario, null: false, foreign_key: true, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.decimal :expected_monthly_payout, precision: 19, scale: 4
      t.date :payout_start_date

      t.timestamps
    end

    add_index :retirement_scenario_pension_sources,
              [:retirement_scenario_id, :account_id],
              unique: true,
              name: "idx_pension_sources_scenario_account"
  end
end
