class CryptosController < ApplicationController
  include AccountableResource

  permitted_accountable_attributes :id, :acquisition_date, :expected_growth_rate
end
