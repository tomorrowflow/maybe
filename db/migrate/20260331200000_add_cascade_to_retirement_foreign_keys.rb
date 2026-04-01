class AddCascadeToRetirementForeignKeys < ActiveRecord::Migration[7.2]
  def up
    # retirement_scenario_pension_sources → retirement_scenarios
    remove_foreign_key :retirement_scenario_pension_sources, :retirement_scenarios
    add_foreign_key :retirement_scenario_pension_sources, :retirement_scenarios, on_delete: :cascade

    # retirement_scenario_pension_sources → accounts
    remove_foreign_key :retirement_scenario_pension_sources, :accounts
    add_foreign_key :retirement_scenario_pension_sources, :accounts, on_delete: :cascade

    # retirement_scenario_snapshots → retirement_scenarios
    remove_foreign_key :retirement_scenario_snapshots, :retirement_scenarios
    add_foreign_key :retirement_scenario_snapshots, :retirement_scenarios, on_delete: :cascade

    # retirement_scenario_persons → retirement_scenarios
    remove_foreign_key :retirement_scenario_persons, :retirement_scenarios
    add_foreign_key :retirement_scenario_persons, :retirement_scenarios, on_delete: :cascade

    # retirement_scenario_persons → persons
    remove_foreign_key :retirement_scenario_persons, column: :person_id
    add_foreign_key :retirement_scenario_persons, :persons, column: :person_id, on_delete: :cascade
  end

  def down
    remove_foreign_key :retirement_scenario_pension_sources, :retirement_scenarios
    add_foreign_key :retirement_scenario_pension_sources, :retirement_scenarios

    remove_foreign_key :retirement_scenario_pension_sources, :accounts
    add_foreign_key :retirement_scenario_pension_sources, :accounts

    remove_foreign_key :retirement_scenario_snapshots, :retirement_scenarios
    add_foreign_key :retirement_scenario_snapshots, :retirement_scenarios

    remove_foreign_key :retirement_scenario_persons, :retirement_scenarios
    add_foreign_key :retirement_scenario_persons, :retirement_scenarios

    remove_foreign_key :retirement_scenario_persons, column: :person_id
    add_foreign_key :retirement_scenario_persons, :persons, column: :person_id
  end
end
