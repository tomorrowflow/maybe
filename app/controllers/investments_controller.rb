class InvestmentsController < ApplicationController
  include AccountableResource

  permitted_accountable_attributes :id, :retirement_date, :expected_monthly_payout
end
