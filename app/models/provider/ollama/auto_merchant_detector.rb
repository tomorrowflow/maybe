class Provider::Ollama::AutoMerchantDetector
  def initialize(client, model:, transactions:, user_merchants:)
    @client = client
    @model = model
    @transactions = transactions
    @user_merchants = user_merchants
  end

  def auto_detect_merchants
    payload = {
      model: model,
      messages: [ { role: "user", content: prompt } ],
      format: "json",
      stream: false
    }

    response = client.chat(payload)
    response_data = response.is_a?(Array) ? response.first : response

    build_response(extract_merchants(response_data))
  end

  private
    attr_reader :client, :model, :transactions, :user_merchants

    AutoDetectedMerchant = Provider::LlmConcept::AutoDetectedMerchant

    def build_response(merchants)
      merchants.map do |merchant|
        AutoDetectedMerchant.new(
          transaction_id: merchant["transaction_id"],
          business_name: normalize_value(merchant["business_name"]),
          business_url: normalize_value(merchant["business_url"])
        )
      end
    end

    def normalize_value(value)
      return nil if value.nil? || value == "null" || value.to_s.downcase == "null"

      value
    end

    def extract_merchants(response)
      content = response.dig("message", "content")
      return [] unless content.present?

      parsed = JSON.parse(content)
      parsed["merchants"] || []
    rescue JSON::ParserError
      []
    end

    def prompt
      <<~PROMPT
        You are an assistant to a consumer personal finance app. Your job is to detect merchant business names and website URLs from transaction data.

        Rules:
        - Return 1 result per transaction
        - Correlate each transaction by ID (transaction_id)
        - Do not include subdomain in business_url (use "amazon.com" not "www.amazon.com")
        - User merchants are manual entries and should only be used in 100% clear cases
        - Be slightly pessimistic. Favor returning "null" over false positives.
        - NEVER return a name or URL for generic transaction names (e.g., "Paycheck", "Laundromat", "Grocery store")

        Determining values:
        1. First attempt to determine name + URL from your knowledge of global businesses
        2. If no certain match, attempt to match one of the user-provided merchants
        3. If no match, return "null"

        User merchants:
        #{user_merchants.to_json}

        Transactions to analyze:
        #{transactions.to_json}

        Respond with a JSON object in this exact format:
        {
          "merchants": [
            {"transaction_id": "id1", "business_name": "Name or null", "business_url": "url.com or null"},
            {"transaction_id": "id2", "business_name": "Name or null", "business_url": "url.com or null"}
          ]
        }
      PROMPT
    end
end
