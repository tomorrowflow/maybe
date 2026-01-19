class Provider::Ollama::ChatStreamParser
  Error = Class.new(StandardError)

  def initialize(event, model:, accumulated_text: "", accumulated_tool_calls: [])
    @event = event
    @model = model
    @accumulated_text = accumulated_text
    @accumulated_tool_calls = accumulated_tool_calls
  end

  def parsed
    return nil unless event.is_a?(Hash)

    message = event.dig("message")
    return nil unless message

    content = message.dig("content")
    tool_calls = message.dig("tool_calls")
    done = event.dig("done")

    # Debug logging to see what the model is actually returning
    if done
      Rails.logger.info "[Ollama ChatStreamParser] Final event: #{event.inspect}"
      Rails.logger.info "[Ollama ChatStreamParser] Message keys: #{message.keys.inspect}"
    elsif message.present? && content.blank?
      Rails.logger.info "[Ollama ChatStreamParser] Message with no content, keys: #{message.keys.inspect}, message: #{message.inspect}"
    end

    if done
      Chunk.new(type: "response", data: build_response)
    elsif tool_calls.present?
      # Return tool_calls chunk so they can be accumulated
      Chunk.new(type: "tool_calls", data: tool_calls)
    elsif content.present?
      Chunk.new(type: "output_text", data: content)
    end
  end

  private
    attr_reader :event, :model, :accumulated_text, :accumulated_tool_calls

    Chunk = Provider::LlmConcept::ChatStreamChunk

    def build_response
      # For the final event, create a response with the accumulated text and tool_calls
      # since the final event may have empty content and no tool_calls
      Rails.logger.info "[Ollama ChatStreamParser] Building final response with accumulated_text length: #{accumulated_text.length}, accumulated_tool_calls count: #{accumulated_tool_calls.length}"

      response_with_accumulated = event.merge(
        "message" => event["message"].merge(
          "content" => accumulated_text,
          "tool_calls" => accumulated_tool_calls.presence || event.dig("message", "tool_calls")
        ).compact
      )
      Provider::Ollama::ChatParser.new(response_with_accumulated, model: model).parsed
    end
end
