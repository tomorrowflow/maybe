class CreateRetirementPlanningModule < ActiveRecord::Migration[7.2]
  def change
    # ==========================================
    # Drop old retirement tables (if they exist from prior migrations)
    # ==========================================
    drop_table :retirement_scenario_linked_payments, if_exists: true
    drop_table :retirement_scenario_milestones, if_exists: true
    drop_table :retirement_scenario_persons, if_exists: true
    drop_table :retirement_scenario_snapshots, if_exists: true
    drop_table :retirement_scenario_pension_sources, if_exists: true
    drop_table :retirement_scenarios, if_exists: true

    # ==========================================
    # Main scenario table
    # ==========================================
    create_table :retirement_scenarios, id: :uuid do |t|
      t.references :family, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.references :person, foreign_key: { on_delete: :nullify }, type: :uuid

      # Metadata
      t.string :name, null: false
      t.text :description
      t.boolean :is_primary, default: false
      t.string :scenario_type, default: "household", null: false
      t.date :calculation_date, null: false

      # Expense assumptions
      t.decimal :retirement_monthly_expenses, precision: 19, scale: 4

      # Portfolio growth (mean for Monte Carlo)
      t.decimal :portfolio_growth_rate, precision: 5, scale: 2, default: 7.0
      t.decimal :portfolio_growth_std_dev, precision: 5, scale: 2, default: 15.0
      t.decimal :inflation_rate, precision: 5, scale: 2, default: 3.0

      # Monte Carlo settings
      t.integer :simulation_count, default: 1000
      t.integer :target_age, default: 90

      # Cash flow overrides (optional manual entries)
      t.decimal :after_tax_monthly_income, precision: 19, scale: 4
      t.decimal :monthly_living_expenses, precision: 19, scale: 4
      t.decimal :monthly_contribution, precision: 10, scale: 2
      t.integer :analysis_year

      # Cached Monte Carlo results
      t.decimal :monte_carlo_success_rate, precision: 5, scale: 2
      t.datetime :monte_carlo_ran_at
      t.jsonb :monte_carlo_results, default: {}
      t.string :monte_carlo_status, default: "pending"

      # Cached calculated outputs
      t.decimal :current_portfolio_value, precision: 19, scale: 4
      t.decimal :total_pension_income, precision: 10, scale: 2

      # Extensibility
      t.jsonb :assumptions, default: {}

      t.timestamps
    end

    add_index :retirement_scenarios, [ :family_id, :is_primary ]
    add_index :retirement_scenarios, :monte_carlo_status

    # ==========================================
    # Per-person income streams
    # ==========================================
    create_table :retirement_scenario_persons, id: :uuid do |t|
      t.references :retirement_scenario, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.references :person, null: false, foreign_key: { on_delete: :cascade }, type: :uuid

      # Salary
      t.decimal :current_annual_salary, precision: 10, scale: 2
      t.date :salary_end_date

      # Retirement
      t.integer :retirement_age
      t.date :target_retirement_date

      # State pension
      t.date :state_pension_start_date
      t.decimal :state_pension_monthly, precision: 10, scale: 2

      # Post-retirement part-time income
      t.decimal :post_retirement_income_monthly, precision: 10, scale: 2
      t.date :post_retirement_income_start_date
      t.date :post_retirement_income_end_date

      t.timestamps
    end

    add_index :retirement_scenario_persons, [ :retirement_scenario_id, :person_id ], unique: true, name: "idx_retirement_scenario_persons_unique"

    # ==========================================
    # Linked pension accounts (sole pension data source)
    # ==========================================
    create_table :retirement_scenario_pension_sources, id: :uuid do |t|
      t.references :retirement_scenario, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.decimal :expected_monthly_payout, precision: 19, scale: 4
      t.date :payout_start_date

      t.timestamps
    end

    add_index :retirement_scenario_pension_sources, [ :retirement_scenario_id, :account_id ], unique: true, name: "idx_retirement_pension_sources_unique"

    # ==========================================
    # Financial milestones (debt payoff, Bauspar transitions, etc.)
    # ==========================================
    create_table :retirement_scenario_milestones, id: :uuid do |t|
      t.references :retirement_scenario, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :milestone_type, null: false
      t.date :date, null: false
      t.string :label
      t.decimal :amount, precision: 19, scale: 4
      t.references :account, foreign_key: { on_delete: :nullify }, type: :uuid
      t.boolean :auto_detected, default: false

      t.timestamps
    end

    add_index :retirement_scenario_milestones, [ :retirement_scenario_id, :date ], name: "idx_retirement_milestones_scenario_date"
    add_index :retirement_scenario_milestones, :milestone_type

    # ==========================================
    # Linked recurring payments
    # ==========================================
    create_table :retirement_scenario_linked_payments, id: :uuid do |t|
      t.references :retirement_scenario, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :transaction_name, null: false
      t.decimal :monthly_amount, precision: 19, scale: 4
      t.references :account, foreign_key: { on_delete: :nullify }, type: :uuid
      t.boolean :is_regular_expense, default: false

      t.timestamps
    end

    add_index :retirement_scenario_linked_payments, [ :retirement_scenario_id, :transaction_name ], unique: true, name: "idx_retirement_linked_payments_unique"

    # ==========================================
    # Historical snapshots (progress tracking)
    # ==========================================
    create_table :retirement_scenario_snapshots, id: :uuid do |t|
      t.references :retirement_scenario, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.date :snapshot_date, null: false

      # Portfolio state
      t.decimal :current_portfolio_value, precision: 19, scale: 4
      t.decimal :projected_portfolio_value, precision: 19, scale: 4
      t.decimal :total_pension_income, precision: 19, scale: 4

      # Monte Carlo result at snapshot time
      t.decimal :monte_carlo_success_rate, precision: 5, scale: 2

      # Assumptions at time of snapshot
      t.decimal :growth_rate_assumption, precision: 5, scale: 2
      t.decimal :growth_std_dev_assumption, precision: 5, scale: 2
      t.decimal :inflation_rate_assumption, precision: 5, scale: 2
      t.decimal :monthly_contribution_assumption, precision: 19, scale: 4
      t.integer :simulation_count_assumption
      t.integer :target_age_assumption

      t.string :notes

      t.timestamps
    end

    add_index :retirement_scenario_snapshots, [ :retirement_scenario_id, :snapshot_date ], unique: true, name: "idx_retirement_snapshots_unique"
    add_index :retirement_scenario_snapshots, :snapshot_date
  end
end
