class Provider::Ollama::ChatStreamParser
  Error = Class.new(StandardError)

  def initialize(event, model:, accumulated_text: "")
    @event = event
    @model = model
    @accumulated_text = accumulated_text
  end

  def parsed
    return nil unless event.is_a?(Hash)

    message = event.dig("message")
    return nil unless message

    content = message.dig("content")
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
    elsif content.present?
      Chunk.new(type: "output_text", data: content)
    end
  end

  private
    attr_reader :event, :model, :accumulated_text

    Chunk = Provider::LlmConcept::ChatStreamChunk

    def build_response
      # For the final event, create a response with the accumulated text
      # since the final event has empty content
      Rails.logger.info "[Ollama ChatStreamParser] Building final response with accumulated_text length: #{accumulated_text.length}"

      response_with_content = event.merge(
        "message" => event["message"].merge("content" => accumulated_text)
      )
      Provider::Ollama::ChatParser.new(response_with_content, model: model).parsed
    end
end
