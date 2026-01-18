class LoansController < ApplicationController
  include AccountableResource

  permitted_accountable_attributes(
    :id,
    :rate_type,
    :interest_rate,
    :effective_interest_rate,
    :term_months,
    :initial_balance,
    :fixed_rate_end_date,
    :maturity_date,
    :extra_payment_allowance_percent
  )
end
