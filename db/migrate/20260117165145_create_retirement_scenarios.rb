class CreateRetirementScenarios < ActiveRecord::Migration[7.2]
  def change
    create_table :retirement_scenarios, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid

      # Metadata
      t.string :name, null: false
      t.text :description
      t.boolean :is_primary, default: false

      # Snapshot
      t.date :calculation_date, null: false

      # Basic assumptions - Expenses
      t.decimal :retirement_monthly_expenses, precision: 10, scale: 2

      # Basic assumptions - Income Streams
      t.date :salary_end_date
      t.decimal :current_annual_salary, precision: 10, scale: 2

      # German Pension Products
      t.date :gesetzliche_rente_start_date
      t.decimal :gesetzliche_rente_monthly, precision: 10, scale: 2
      t.decimal :riester_monthly, precision: 10, scale: 2
      t.decimal :ruerup_monthly, precision: 10, scale: 2
      t.decimal :betriebsrente_monthly, precision: 10, scale: 2

      # Generic pension
      t.date :other_pension_start_date
      t.decimal :other_pension_monthly, precision: 10, scale: 2

      # Portfolio withdrawal (ONLY for gap between income and expenses)
      t.decimal :portfolio_withdrawal_rate, precision: 5, scale: 2, default: 4.0

      # Calculated outputs
      t.decimal :current_portfolio_value, precision: 19, scale: 4
      t.decimal :total_pension_income, precision: 10, scale: 2
      t.decimal :income_gap_monthly, precision: 10, scale: 2
      t.decimal :required_portfolio_value, precision: 19, scale: 4
      t.decimal :portfolio_gap, precision: 19, scale: 4
      t.date :projected_retirement_date

      # Extensibility
      t.jsonb :assumptions, default: {}
      t.jsonb :calculation_results, default: {}

      t.timestamps
    end

    add_index :retirement_scenarios, [:family_id, :is_primary]
    add_index :retirement_scenarios, :projected_retirement_date
  end
end
