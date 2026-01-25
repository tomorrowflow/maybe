class PrivateLoansController < ApplicationController
  include AccountableResource

  permitted_accountable_attributes(
    :id,
    :principal_amount,
    :interest_rate,
    :rate_type,
    :term_months,
    :repayment_type,
    :start_date,
    :maturity_date,
    :borrower_name,
    :borrower_notes,
    :contract_number,
    :has_written_contract,
    :has_collateral,
    :collateral_description
  )
end
