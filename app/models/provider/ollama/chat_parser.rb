class Provider::Ollama::ChatParser
  Error = Class.new(StandardError)

  def initialize(response, model:)
    @response = response
    @model = model
  end

  def parsed
    ChatResponse.new(
      id: generate_response_id,
      model: model,
      messages: messages,
      function_requests: function_requests
    )
  end

  private
    attr_reader :response, :model

    ChatResponse = Provider::LlmConcept::ChatResponse
    ChatMessage = Provider::LlmConcept::ChatMessage
    ChatFunctionRequest = Provider::LlmConcept::ChatFunctionRequest

    def generate_response_id
      SecureRandom.uuid
    end

    def messages
      message = response.dig("message")
      return [] unless message

      content = message.dig("content")
      return [] if content.blank?

      [
        ChatMessage.new(
          id: SecureRandom.uuid,
          output_text: content
        )
      ]
    end

    def function_requests
      message = response.dig("message")
      return [] unless message

      tool_calls = message.dig("tool_calls")
      return [] unless tool_calls.is_a?(Array)

      tool_calls.map do |tool_call|
        function = tool_call.dig("function")
        next unless function

        ChatFunctionRequest.new(
          id: SecureRandom.uuid,
          call_id: SecureRandom.uuid,
          function_name: function.dig("name"),
          function_args: function.dig("arguments").is_a?(Hash) ? function.dig("arguments").to_json : function.dig("arguments")
        )
      end.compact
    end
end
