class InvestmentsController < ApplicationController
  include AccountableResource

  permitted_accountable_attributes :id, :retirement_date, :expected_monthly_payout, :expected_growth_rate, :opening_date,
                                   :can_cash_out_early, :has_surrender_value, :surrender_value, :early_cashout_date,
                                   :monthly_contribution
end
