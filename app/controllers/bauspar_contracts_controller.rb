class BausparContractsController < ApplicationController
  include AccountableResource

  permitted_accountable_attributes(
    :id,
    :bausparsumme,
    :provider,
    :contract_number,
    :phase,
    :savings_interest_rate,
    :loan_interest_rate
  )
end
