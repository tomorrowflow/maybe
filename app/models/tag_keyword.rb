class TagKeyword < ApplicationRecord
  belongs_to :family
  belongs_to :tag

  validates :keyword, presence: true
  validates :keyword, uniqueness: { scope: :family_id, case_sensitive: false }
  validates :match_type, presence: true, inclusion: { in: %w[contains starts_with exact] }

  before_save :normalize_keyword

  scope :for_family, ->(family) { where(family: family) }

  class << self
    def match_tags(family, transaction_name)
      return [] if transaction_name.blank?

      name_lower = transaction_name.downcase.strip
      matched_tags = []

      # Check exact matches first
      for_family(family).where(match_type: "exact").each do |tk|
        matched_tags << tk.tag if name_lower == tk.keyword
      end

      # Check starts_with matches
      for_family(family).where(match_type: "starts_with").each do |tk|
        matched_tags << tk.tag if name_lower.start_with?(tk.keyword)
      end

      # Check contains matches (most common)
      for_family(family).where(match_type: "contains").each do |tk|
        matched_tags << tk.tag if name_lower.include?(tk.keyword)
      end

      matched_tags.uniq
    end

    def seed_defaults(family)
      default_mappings = {
        "subscription" => %w[netflix spotify hulu disney+ hbo amazon\ prime apple\ music],
        "recurring" => %w[subscription monthly yearly annual membership],
        "online" => %w[amazon ebay etsy shopify online digital],
        "cash" => %w[atm cash withdrawal],
        "work" => %w[salary payroll deposit direct\ deposit employer],
        "health" => %w[pharmacy doctor hospital medical dental health gym fitness]
      }

      default_mappings.each do |tag_name, keywords|
        tag = family.tags.find_or_create_by!(name: tag_name)

        keywords.each do |keyword|
          find_or_create_by(family: family, keyword: keyword.downcase) do |tk|
            tk.tag = tag
            tk.match_type = "contains"
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
