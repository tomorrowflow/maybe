class Provider::Ollama::AutoCategorizer
  def initialize(client, model:, transactions: [], user_categories: [])
    @client = client
    @model = model
    @transactions = transactions
    @user_categories = user_categories
  end

  def auto_categorize
    payload = {
      model: model,
      messages: [ { role: "user", content: prompt } ],
      format: "json",
      stream: false
    }

    response = client.chat(payload)
    response_data = response.is_a?(Array) ? response.first : response

    build_response(extract_categorizations(response_data))
  end

  private
    attr_reader :client, :model, :transactions, :user_categories

    AutoCategorization = Provider::LlmConcept::AutoCategorization

    def build_response(categorizations)
      categorizations.map do |categorization|
        AutoCategorization.new(
          transaction_id: categorization["transaction_id"],
          category_name: normalize_category_name(categorization["category_name"])
        )
      end
    end

    def normalize_category_name(category_name)
      return nil if category_name.nil? || category_name == "null" || category_name.to_s.downcase == "null"

      category_name
    end

    def extract_categorizations(response)
      content = response.dig("message", "content")
      return [] unless content.present?

      parsed = JSON.parse(content)
      parsed["categorizations"] || []
    rescue JSON::ParserError
      []
    end

    def prompt
      <<~PROMPT
        You are an assistant to a consumer personal finance app. You will be provided a list of transactions and a list of categories. Your job is to auto-categorize each transaction.

        Rules:
        - Return 1 result per transaction
        - Correlate each transaction by ID (transaction_id)
        - Attempt to match the most specific category possible (subcategory over parent category)
        - Category and transaction classifications should match (if transaction is "expense", category must be "expense")
        - If you don't know the category, return "null"
        - Favor "null" over false positives. Only match if 60%+ confident.

        Available categories:
        #{user_categories.to_json}

        Transactions to categorize:
        #{transactions.to_json}

        Respond with a JSON object in this exact format:
        {
          "categorizations": [
            {"transaction_id": "id1", "category_name": "Category Name or null"},
            {"transaction_id": "id2", "category_name": "Category Name or null"}
          ]
        }
      PROMPT
    end
end
