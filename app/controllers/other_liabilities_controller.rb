class OtherLiabilitiesController < ApplicationController
  include AccountableResource

  permitted_accountable_attributes :id, :start_date, :interest_rate
end
