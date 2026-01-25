class Provider::Ollama::AutoTagger
  def initialize(client, model:, transactions: [], user_tags: [])
    @client = client
    @model = model
    @transactions = transactions
    @user_tags = user_tags
  end

  def auto_tag
    payload = {
      model: model,
      messages: [ { role: "user", content: prompt } ],
      format: "json",
      stream: false
    }

    response = client.chat(payload)
    response_data = response.is_a?(Array) ? response.first : response

    build_response(extract_taggings(response_data))
  end

  private
    attr_reader :client, :model, :transactions, :user_tags

    AutoTagging = Provider::LlmConcept::AutoTagging

    def build_response(taggings)
      taggings.map do |tagging|
        tag_names = tagging["tag_names"] || []
        tag_names = tag_names.reject { |name| name.nil? || name == "null" || name.to_s.downcase == "null" || name.blank? }

        AutoTagging.new(
          transaction_id: tagging["transaction_id"],
          tag_names: tag_names
        )
      end
    end

    def extract_taggings(response)
      content = response.dig("message", "content")
      return [] unless content.present?

      parsed = JSON.parse(content)
      parsed["taggings"] || []
    rescue JSON::ParserError
      []
    end

    def prompt
      <<~PROMPT
        You are an assistant to a consumer personal finance app. You will be provided a list of transactions and a list of tags. Your job is to auto-tag each transaction with relevant tags.

        Rules:
        - Return 1 result per transaction (but each result can have multiple tags)
        - Correlate each transaction by ID (transaction_id)
        - A transaction can have 0 or more tags
        - Only assign tags that are actually relevant to the transaction
        - If you don't know what tags to assign, return an empty array
        - Favor empty array over false positives. Only assign if 60%+ confident.
        - Tags help users organize and find transactions
        - Common patterns: "recurring", "subscription", "work", "personal", "cash", "online"

        Available tags:
        #{user_tags.to_json}

        Transactions to tag:
        #{transactions.to_json}

        Respond with a JSON object in this exact format:
        {
          "taggings": [
            {"transaction_id": "id1", "tag_names": ["tag1", "tag2"]},
            {"transaction_id": "id2", "tag_names": []}
          ]
        }
      PROMPT
    end
end
