class Provider::Openai::AutoTagger
  def initialize(client, transactions: [], user_tags: [])
    @client = client
    @transactions = transactions
    @user_tags = user_tags
  end

  def auto_tag
    response = client.responses.create(parameters: {
      model: "gpt-4.1-mini",
      input: [ { role: "developer", content: developer_message } ],
      text: {
        format: {
          type: "json_schema",
          name: "auto_tag_personal_finance_transactions",
          strict: true,
          schema: json_schema
        }
      },
      instructions: instructions
    })

    Rails.logger.info("Tokens used to auto-tag transactions: #{response.dig("usage").dig("total_tokens")}")

    build_response(extract_taggings(response))
  end

  private
    attr_reader :client, :transactions, :user_tags

    AutoTagging = Provider::LlmConcept::AutoTagging

    def build_response(taggings)
      taggings.map do |tagging|
        tag_names = tagging.dig("tag_names") || []
        tag_names = tag_names.reject { |name| name == "null" || name.blank? }

        AutoTagging.new(
          transaction_id: tagging.dig("transaction_id"),
          tag_names: tag_names
        )
      end
    end

    def extract_taggings(response)
      response_json = JSON.parse(response.dig("output")[0].dig("content")[0].dig("text"))
      response_json.dig("taggings")
    end

    def json_schema
      {
        type: "object",
        properties: {
          taggings: {
            type: "array",
            description: "An array of auto-taggings for each transaction",
            items: {
              type: "object",
              properties: {
                transaction_id: {
                  type: "string",
                  description: "The internal ID of the original transaction",
                  enum: transactions.map { |t| t[:id] }
                },
                tag_names: {
                  type: "array",
                  description: "The matched tag names for the transaction (can be multiple), or empty if no match",
                  items: {
                    type: "string",
                    enum: [ *user_tags.map { |t| t[:name] }, "null" ]
                  }
                }
              },
              required: [ "transaction_id", "tag_names" ],
              additionalProperties: false
            }
          }
        },
        required: [ "taggings" ],
        additionalProperties: false
      }
    end

    def developer_message
      <<~MESSAGE.strip_heredoc
        Here are the user's available tags in JSON format:

        ```json
        #{user_tags.to_json}
        ```

        Use the available tags to auto-tag the following transactions:

        ```json
        #{transactions.to_json}
        ```
      MESSAGE
    end

    def instructions
      <<~INSTRUCTIONS.strip_heredoc
        You are an assistant to a consumer personal finance app. You will be provided a list
        of the user's transactions and a list of the user's tags. Your job is to auto-tag
        each transaction with relevant tags.

        Closely follow ALL the rules below while auto-tagging:

        - Return 1 result per transaction (but each result can have multiple tags)
        - Correlate each transaction by ID (transaction_id)
        - A transaction can have 0 or more tags
        - Only assign tags that are actually relevant to the transaction
        - If you don't know what tags to assign, return an empty array
          - You should always favor empty over false positives
          - Be slightly pessimistic. Only assign a tag if you're 60%+ confident it is relevant.
        - Each transaction has varying metadata that can be used to determine relevant tags
        - Tags are meant to help users organize and find transactions
          - Common tag patterns: "recurring", "subscription", "work", "personal", "cash", "online"
      INSTRUCTIONS
    end
end
