class CategoryKeyword < ApplicationRecord
  belongs_to :family
  belongs_to :category

  validates :keyword, presence: true
  validates :keyword, uniqueness: { scope: :family_id, case_sensitive: false }
  validates :match_type, presence: true, inclusion: { in: %w[contains starts_with exact] }

  before_save :normalize_keyword

  scope :for_family, ->(family) { where(family: family) }

  class << self
    def match_category(family, transaction_name)
      return nil if transaction_name.blank?

      name_lower = transaction_name.downcase.strip

      # Check exact matches first
      exact_match = for_family(family).where(match_type: "exact").find do |ck|
        name_lower == ck.keyword
      end
      return exact_match.category if exact_match

      # Check starts_with matches
      starts_with_match = for_family(family).where(match_type: "starts_with").find do |ck|
        name_lower.start_with?(ck.keyword)
      end
      return starts_with_match.category if starts_with_match

      # Check contains matches (most common)
      contains_match = for_family(family).where(match_type: "contains").find do |ck|
        name_lower.include?(ck.keyword)
      end
      return contains_match.category if contains_match

      nil
    end

    def seed_defaults(family)
      default_mappings = {
        "Food & Drink" => %w[restaurant cafe coffee starbucks mcdonalds burger pizza subway],
        "Shopping" => %w[amazon walmart target costco ebay shop store],
        "Transportation" => %w[uber lyft taxi gas shell chevron exxon bp],
        "Entertainment" => %w[netflix spotify hulu disney+ hbo cinema movie theater],
        "Groceries" => %w[grocery kroger safeway trader whole\ foods aldi],
        "Rent & Utilities" => %w[electric water gas utility power internet comcast verizon],
        "Healthcare" => %w[pharmacy cvs walgreens doctor hospital medical dental],
        "Travel" => %w[airline hotel airbnb flight booking expedia]
      }

      default_mappings.each do |category_name, keywords|
        category = family.categories.find_by(name: category_name)
        next unless category

        keywords.each do |keyword|
          find_or_create_by(family: family, keyword: keyword.downcase) do |ck|
            ck.category = category
            ck.match_type = "contains"
          end
        end
      end
    end
  end

  private

  def normalize_keyword
    self.keyword = keyword.downcase.strip if keyword.present?
  end
end
