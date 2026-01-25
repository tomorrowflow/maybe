class Category < ApplicationRecord
  has_many :transactions, dependent: :nullify, class_name: "Transaction"
  has_many :import_mappings, as: :mappable, dependent: :destroy, class_name: "Import::Mapping"

  belongs_to :family

  has_many :budget_categories, dependent: :destroy
  has_many :subcategories, class_name: "Category", foreign_key: :parent_id, dependent: :nullify
  belongs_to :parent, class_name: "Category", optional: true

  validates :name, :color, :lucide_icon, :family, presence: true
  validates :name, uniqueness: { scope: :family_id }

  validate :category_level_limit
  validate :nested_category_matches_parent_classification

  before_save :inherit_color_from_parent

  scope :alphabetically, -> { order(:name) }
  scope :roots, -> { where(parent_id: nil) }
  scope :incomes, -> { where(classification: "income") }
  scope :expenses, -> { where(classification: "expense") }

  COLORS = %w[#e99537 #4da568 #6471eb #db5a54 #df4e92 #c44fe9 #eb5429 #61c9ea #805dee #6ad28a]

  UNCATEGORIZED_COLOR = "#737373"
  TRANSFER_COLOR = "#444CE7"
  PAYMENT_COLOR = "#db5a54"
  TRADE_COLOR = "#e99537"

  class Group
    attr_reader :category, :subcategories

    delegate :name, :color, to: :category

    def self.for(categories)
      categories.select { |category| category.parent_id.nil? }.map do |category|
        new(category, category.subcategories)
      end
    end

    def initialize(category, subcategories = nil)
      @category = category
      @subcategories = subcategories || []
    end
  end

  class << self
    def icon_codes
      %w[bus circle-dollar-sign ambulance apple award baby battery lightbulb bed-single beer bluetooth book briefcase building credit-card camera utensils cooking-pot cookie dices drama dog drill drum dumbbell gamepad-2 graduation-cap house hand-helping ice-cream-cone phone piggy-bank pill pizza printer puzzle ribbon shopping-cart shield-plus ticket trees]
    end

    def bootstrap!
      default_categories.each do |cat_data|
        # Create or find the parent category
        parent = find_or_create_by!(name: cat_data[:name]) do |category|
          category.color = cat_data[:color]
          category.classification = cat_data[:classification]
          category.lucide_icon = cat_data[:icon]
        end

        # Create subcategories
        cat_data[:subcategories]&.each do |sub_name|
          find_or_create_by!(name: sub_name) do |sub|
            sub.parent = parent
            sub.color = parent.color
            sub.lucide_icon = parent.lucide_icon
            sub.classification = parent.classification
          end
        end
      end
    end

    def uncategorized
      new(
        name: "Uncategorized",
        color: UNCATEGORIZED_COLOR,
        lucide_icon: "circle-dashed"
      )
    end

    private
      def default_categories
        [
          {
            name: "Finances & Insurances",
            color: "#6471eb",
            icon: "credit-card",
            classification: "expense",
            subcategories: [
              "Insurances",
              "Interest & Investments",
              "Real Estate",
              "Transfer",
              "ATM",
              "Bank Charges",
              "Job & Business",
              "Savings",
              "Services",
              "Child Allowance & Alimony",
              "Credits & Financing"
            ]
          },
          {
            name: "Leisure & Entertainment",
            color: "#df4e92",
            icon: "drama",
            classification: "expense",
            subcategories: [
              "Trips & Activities",
              "Media",
              "Lottery",
              "Vacation",
              "Arts & Culture",
              "Associations",
              "Sports",
              "Streaming",
              "Hobby"
            ]
          },
          {
            name: "Living",
            color: "#4da568",
            icon: "house",
            classification: "expense",
            subcategories: [
              "Shopping",
              "Groceries",
              "Rent & Utilities",
              "Home Improvement",
              "Furniture",
              "Healthcare",
              "Personal Care",
              "Food & Drink",
              "Clothing"
            ]
          },
          {
            name: "Mobility",
            color: "#61c9ea",
            icon: "bus",
            classification: "expense",
            subcategories: [
              "Gas & Charging Station",
              "Car & Motorcycle",
              "Transport",
              "Bicycle & Scooter",
              "Parking",
              "Car Insurance",
              "Car Maintenance"
            ]
          },
          {
            name: "State & Authority",
            color: "#805dee",
            icon: "building",
            classification: "expense",
            subcategories: [
              "Social Benefits",
              "Taxes",
              "Office & Administration Costs",
              "Broadcasting Fee",
              "Fees & Fines"
            ]
          },
          {
            name: "Income",
            color: "#e99537",
            icon: "circle-dollar-sign",
            classification: "income",
            subcategories: [
              "Salary",
              "Bonus",
              "Investment Income",
              "Rental Income",
              "Side Income",
              "Refunds",
              "Gifts Received"
            ]
          }
        ]
      end
  end

  def inherit_color_from_parent
    if subcategory?
      self.color = parent.color
    end
  end

  def replace_and_destroy!(replacement)
    transaction do
      transactions.update_all category_id: replacement&.id
      destroy!
    end
  end

  def parent?
    subcategories.any?
  end

  def subcategory?
    parent.present?
  end

  private
    def category_level_limit
      if (subcategory? && parent.subcategory?) || (parent? && subcategory?)
        errors.add(:parent, "can't have more than 2 levels of subcategories")
      end
    end

    def nested_category_matches_parent_classification
      if subcategory? && parent.classification != classification
        errors.add(:parent, "must have the same classification as its parent")
      end
    end

    def monetizable_currency
      family.currency
    end
end
