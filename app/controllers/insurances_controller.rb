class InsurancesController < ApplicationController
  include AccountableResource

  permitted_accountable_attributes(
    :id,
    :provider,
    :policy_number,
    :premium_amount,
    :premium_frequency,
    :maturity_date,
    :cash_surrender_value
  )
end
