class Measurement
  include ActiveModel::Validations
  include ActiveSupport::NumberHelper

  attr_reader :value, :unit

  VALID_UNITS = %w[sqft sqm mi km].freeze

  UNIT_LABELS = {
    "sqft" => "sq ft",
    "sqm" => "m\u00B2",
    "mi" => "mi",
    "km" => "km"
  }.freeze

  validates :unit, inclusion: { in: VALID_UNITS }
  validates :value, presence: true

  def initialize(value, unit)
    @value = value.to_f
    @unit = unit.to_s.downcase.strip
    validate!
  end

  def to_s
    "#{number_to_delimited(@value.to_i)} #{UNIT_LABELS[@unit] || @unit}"
  end

  def label
    UNIT_LABELS[@unit] || @unit
  end
end
