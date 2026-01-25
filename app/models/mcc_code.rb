class MccCode < ApplicationRecord
  validates :code, presence: true, uniqueness: true, length: { is: 4 }
  validates :description, presence: true

  class << self
    def import_from_csv(file)
      require "csv"

      imported_count = 0
      errors = []

      # Clear existing codes before import
      MccCode.delete_all

      CSV.foreach(file.path, headers: true) do |row|
        code = row["mcc"]&.to_s&.rjust(4, "0")
        description = row["edited_description"] || row["combined_description"] || row["description"]

        next if code.blank? || description.blank?

        begin
          MccCode.create!(
            code: code,
            description: description.strip,
            category_hint: derive_category_hint(description)
          )
          imported_count += 1
        rescue ActiveRecord::RecordInvalid => e
          errors << "Row #{imported_count + 1}: #{e.message}"
        end
      end

      { imported: imported_count, errors: errors }
    end

    def import_from_json(file)
      require "json"

      imported_count = 0
      errors = []

      # Clear existing codes before import
      MccCode.delete_all

      data = JSON.parse(file.read)
      records = data.is_a?(Array) ? data : data.values.flatten

      records.each_with_index do |record, index|
        code = (record["mcc"] || record["code"])&.to_s&.rjust(4, "0")
        description = record["edited_description"] || record["combined_description"] || record["description"]

        next if code.blank? || description.blank?

        begin
          MccCode.create!(
            code: code,
            description: description.strip,
            category_hint: derive_category_hint(description)
          )
          imported_count += 1
        rescue ActiveRecord::RecordInvalid => e
          errors << "Record #{index + 1}: #{e.message}"
        end
      end

      { imported: imported_count, errors: errors }
    end

    def find_by_code(code)
      find_by(code: code.to_s.rjust(4, "0"))
    end

    def suggest_category(code)
      mcc = find_by_code(code)
      mcc&.category_hint
    end

    private

    def derive_category_hint(description)
      desc_lower = description.downcase

      category_mappings = {
        "Food & Dining" => %w[restaurant food dining eating cafe coffee bakery pizza fast],
        "Groceries" => %w[grocery supermarket market food store],
        "Shopping" => %w[store shop retail merchandise department clothing apparel],
        "Transportation" => %w[airline travel railroad taxi bus transit uber lyft],
        "Entertainment" => %w[entertainment theater movie cinema amusement recreation],
        "Utilities" => %w[utility electric gas water phone telecom],
        "Healthcare" => %w[medical doctor hospital pharmacy health dental optical],
        "Education" => %w[school university college education training],
        "Financial Services" => %w[bank financial insurance investment],
        "Home & Garden" => %w[hardware lumber garden furniture home],
        "Auto & Transport" => %w[auto car vehicle gas fuel parking],
        "Travel" => %w[hotel motel lodging travel airport],
        "Personal Care" => %w[salon barber spa beauty cosmetic],
        "Subscriptions" => %w[subscription streaming digital software],
        "Government" => %w[government tax court postal]
      }

      category_mappings.each do |category, keywords|
        return category if keywords.any? { |keyword| desc_lower.include?(keyword) }
      end

      nil
    end
  end
end
