class BausparContractsController < ApplicationController
  include AccountableResource

  permitted_accountable_attributes(
    :id,
    :bausparsumme,
    :provider,
    :contract_number,
    :phase,
    :savings_interest_rate,
    :loan_interest_rate,
    :contract_start_date,
    :expected_allocation_date,
    :actual_allocation_date,
    :current_bewertungszahl,
    :minimum_bewertungszahl,
    :monthly_contribution,
    :minimum_savings_period_months,
    :minimum_savings_percent,
    :wohnungsbauspraemie_eligible,
    :arbeitnehmersparzulage_eligible,
    :wohn_riester_eligible,
    :vermoegenswirksame_leistungen,
    :tariff_name
  )
end
