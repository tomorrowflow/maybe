class AddEnhancementsToBausparContracts < ActiveRecord::Migration[7.2]
  def change
    change_table :bauspar_contracts do |t|
      # Timeline tracking
      t.date :contract_start_date
      t.date :expected_allocation_date
      t.date :actual_allocation_date

      # Bewertungszahl (evaluation number) - scoring system for allocation readiness
      t.decimal :current_bewertungszahl, precision: 10, scale: 2
      t.decimal :minimum_bewertungszahl, precision: 10, scale: 2

      # Monthly contribution (Regelsparbeitrag) - typically 3-4‰ of Bausparsumme
      t.decimal :monthly_contribution, precision: 19, scale: 4

      # Minimum savings period in months (Mindestlaufzeit)
      t.integer :minimum_savings_period_months

      # Minimum savings percentage (default is 40%, but can vary by tariff)
      t.decimal :minimum_savings_percent, precision: 5, scale: 2, default: 40.0

      # State subsidies eligibility
      t.boolean :wohnungsbauspraemie_eligible, default: false
      t.boolean :arbeitnehmersparzulage_eligible, default: false
      t.boolean :wohn_riester_eligible, default: false
      t.boolean :vermoegenswirksame_leistungen, default: false

      # Tariff name (different tariffs have different terms)
      t.string :tariff_name
    end
  end
end
