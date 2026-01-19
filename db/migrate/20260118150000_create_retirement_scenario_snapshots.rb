class CreateRetirementScenarioSnapshots < ActiveRecord::Migration[7.2]
  def change
    create_table :retirement_scenario_snapshots, id: :uuid do |t|
      t.references :retirement_scenario, null: false, foreign_key: true, type: :uuid

      # When the snapshot was taken
      t.date :snapshot_date, null: false

      # Actual values at snapshot time
      t.decimal :current_portfolio_value, precision: 19, scale: 4
      t.decimal :required_portfolio_value, precision: 19, scale: 4
      t.decimal :portfolio_gap, precision: 19, scale: 4
      t.decimal :progress_percent, precision: 8, scale: 2
      t.date :projected_retirement_date
      t.decimal :total_pension_income, precision: 19, scale: 4
      t.decimal :income_gap_monthly, precision: 19, scale: 4

      # What we projected the portfolio would be at this date (from previous snapshot)
      t.decimal :projected_portfolio_value, precision: 19, scale: 4

      # Assumptions used at time of snapshot (for tracking changes)
      t.decimal :growth_rate_assumption, precision: 5, scale: 2
      t.decimal :inflation_rate_assumption, precision: 5, scale: 2
      t.decimal :monthly_contribution_assumption, precision: 19, scale: 4
      t.decimal :withdrawal_rate_assumption, precision: 5, scale: 2

      # Notes or context (optional)
      t.string :notes

      t.timestamps
    end

    add_index :retirement_scenario_snapshots, [ :retirement_scenario_id, :snapshot_date ],
              unique: true, name: "idx_snapshots_on_scenario_and_date"
    add_index :retirement_scenario_snapshots, :snapshot_date
  end
end
