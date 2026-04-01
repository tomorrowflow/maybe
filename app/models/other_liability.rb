class OtherLiability < ApplicationRecord
  include Accountable
  include InterestProjectable

  class << self
    def color
      "#737373"
    end

    def icon
      "minus"
    end

    def classification
      "liability"
    end
  end
end
