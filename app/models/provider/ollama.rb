class Provider::Ollama < Provider
  include LlmConcept

  Error = Class.new(Provider::Error)

  def initialize(host:, model:)
    @host = host
    @model = model
    @client = ::Ollama.new(
      credentials: { address: host },
      options: { server_sent_events: true }
    )
  end

  def supports_model?(model_name)
    model_name == model
  end

  def auto_categorize(transactions: [], user_categories: [])
    with_provider_response do
      raise Error, "Too many transactions to auto-categorize. Max is 25 per request." if transactions.size > 25

      AutoCategorizer.new(
        client,
        model: model,
        transactions: transactions,
        user_categories: user_categories
      ).auto_categorize
    end
  end

  def auto_detect_merchants(transactions: [], user_merchants: [])
    with_provider_response do
      raise Error, "Too many transactions to auto-detect merchants. Max is 25 per request." if transactions.size > 25

      AutoMerchantDetector.new(
        client,
        model: model,
        transactions: transactions,
        user_merchants: user_merchants
      ).auto_detect_merchants
    end
  end

  def chat_response(prompt, model:, instructions: nil, functions: [], function_results: [], streamer: nil, previous_response_id: nil)
    with_provider_response do
      Rails.logger.info "[Ollama] chat_response called with model: #{model}, streamer present: #{!streamer.nil?}"

      chat_config = ChatConfig.new(
        functions: functions,
        function_results: function_results
      )

      messages = chat_config.build_messages(prompt, instructions: instructions)
      tools = chat_config.tools

      Rails.logger.info "[Ollama] Built #{messages.length} messages, #{tools.length} tools"

      if streamer.present?
        stream_chat_response(messages, tools, streamer)
      else
        non_stream_chat_response(messages, tools)
      end
    end
  end

  private
    attr_reader :client, :host, :model

    def non_stream_chat_response(messages, tools)
      payload = {
        model: model,
        messages: messages,
        stream: false
      }
      payload[:tools] = tools if tools.present?

      response = client.chat(payload)
      response_data = response.is_a?(Array) ? response.first : response

      ChatParser.new(response_data, model: model).parsed
    end

    def stream_chat_response(messages, tools, streamer)
      collected_chunks = []
      accumulated_text = ""

      payload = {
        model: model,
        messages: messages,
        stream: true
      }
      payload[:tools] = tools if tools.present?

      Rails.logger.info "[Ollama] Streaming chat with payload: #{payload.except(:messages).inspect}"
      Rails.logger.info "[Ollama] Messages count: #{messages.length}"
      Rails.logger.info "[Ollama] Tools count: #{tools.length}"

      begin
        client.chat(payload, server_sent_events: true) do |event, _raw_response|
          parsed_chunk = ChatStreamParser.new(event, model: model, accumulated_text: accumulated_text).parsed

          unless parsed_chunk.nil?
            # Accumulate text chunks
            if parsed_chunk.type == "output_text"
              accumulated_text += parsed_chunk.data
            end

            streamer.call(parsed_chunk)
            collected_chunks << parsed_chunk
          end
        end

        response_chunk = collected_chunks.find { |chunk| chunk.type == "response" }
        response_chunk&.data
      rescue => e
        Rails.logger.error "[Ollama] Stream error: #{e.class.name}: #{e.message}"
        raise
      end
    end
end
