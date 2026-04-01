class OtherAsset < ApplicationRecord
  include Accountable

  validates :expected_growth_rate, numericality: { greater_than_or_equal_to: -50, less_than_or_equal_to: 100 }, allow_nil: true

  class << self
    def color
      "#12B76A"
    end

    def icon
      "plus"
    end

    def classification
      "asset"
    end
  end
end
