class Provider::Ollama::ChatConfig
  def initialize(functions: [], function_results: [])
    @functions = functions
    @function_results = function_results
  end

  def tools
    return [] if functions.empty?

    functions.map do |fn|
      {
        type: "function",
        function: {
          name: fn[:name],
          description: fn[:description],
          parameters: sanitize_schema(fn[:params_schema])
        }
      }
    end
  end

  def build_messages(prompt, instructions: nil)
    messages = []

    messages << { role: "system", content: instructions } if instructions.present?
    messages << { role: "user", content: prompt }

    function_results.each do |fn_result|
      messages << {
        role: "tool",
        content: fn_result[:output].is_a?(String) ? fn_result[:output] : fn_result[:output].to_json
      }
    end

    messages
  end

  private
    attr_reader :functions, :function_results

    # Ollama doesn't accept empty enum arrays in schemas
    # This method removes properties with empty enums
    def sanitize_schema(schema)
      return schema unless schema.is_a?(Hash)

      schema.each_with_object({}) do |(key, value), sanitized|
        if value.is_a?(Hash)
          # Recursively sanitize the value first
          sanitized_value = sanitize_schema(value)

          # Check if this is an array schema with empty enum in items
          if sanitized_value[:type] == "array" || sanitized_value["type"] == "array"
            items = sanitized_value[:items] || sanitized_value["items"]
            if items.is_a?(Hash)
              enum_value = items[:enum] || items["enum"]
              # Skip this property entirely if items has an empty enum
              if enum_value.is_a?(Array) && enum_value.empty?
                next
              end
            end
          end

          # Check if value itself has an empty enum (not in items)
          enum_value = sanitized_value[:enum] || sanitized_value["enum"]
          if enum_value.is_a?(Array) && enum_value.empty?
            # Skip properties with empty enums
            next
          end

          sanitized[key] = sanitized_value
        else
          sanitized[key] = value
        end
      end
    end
end
