require "test_helper"

class Provider::OllamaTest < ActiveSupport::TestCase
  include LLMInterfaceTest

  setup do
    @subject = @ollama = Provider::Ollama.new(
      host: ENV.fetch("OLLAMA_HOST", "http://localhost:11434"),
      model: ENV.fetch("OLLAMA_MODEL", "llama3.2")
    )
    @subject_model = ENV.fetch("OLLAMA_MODEL", "llama3.2")
  end

  test "supports configured model" do
    assert @ollama.supports_model?(@subject_model)
    assert_not @ollama.supports_model?("gpt-4")
  end

  test "auto categorizes transactions" do
    VCR.use_cassette("ollama/auto_categorize") do
      input_transactions = [
        { id: "1", name: "McDonalds", amount: 20, classification: "expense", merchant: "McDonalds", hint: "Fast Food" },
        { id: "2", name: "Amazon purchase", amount: 100, classification: "expense", merchant: "Amazon" },
        { id: "3", name: "paycheck", amount: 3000, classification: "income" }
      ]

      response = @subject.auto_categorize(
        transactions: input_transactions,
        user_categories: [
          { id: "shopping_id", name: "Shopping", is_subcategory: false, parent_id: nil, classification: "expense" },
          { id: "fast_food_id", name: "Fast Food", is_subcategory: true, parent_id: "restaurants_id", classification: "expense" },
          { id: "income_id", name: "Income", is_subcategory: false, parent_id: nil, classification: "income" }
        ]
      )

      assert response.success?
      assert_equal input_transactions.size, response.data.size
    end
  end

  test "auto detects merchants" do
    VCR.use_cassette("ollama/auto_detect_merchants") do
      input_transactions = [
        { id: "1", name: "McDonalds", amount: 20, classification: "expense" },
        { id: "2", name: "local pub", amount: 20, classification: "expense" },
        { id: "3", name: "Amazon order", amount: 20, classification: "expense" }
      ]

      response = @subject.auto_detect_merchants(
        transactions: input_transactions,
        user_merchants: []
      )

      assert response.success?
      assert_equal input_transactions.size, response.data.size
    end
  end

  test "basic chat response" do
    VCR.use_cassette("ollama/chat/basic_response") do
      response = @subject.chat_response(
        "This is a chat test. If it's working, respond with a single word: Yes",
        model: @subject_model
      )

      assert response.success?
      assert_equal 1, response.data.messages.size
      assert response.data.messages.first.output_text.present?
    end
  end

  test "streams basic chat response" do
    VCR.use_cassette("ollama/chat/basic_streaming_response") do
      collected_chunks = []

      mock_streamer = proc do |chunk|
        collected_chunks << chunk
      end

      response = @subject.chat_response(
        "This is a chat test. If it's working, respond with a single word: Yes",
        model: @subject_model,
        streamer: mock_streamer
      )

      text_chunks = collected_chunks.select { |chunk| chunk.type == "output_text" }
      response_chunks = collected_chunks.select { |chunk| chunk.type == "response" }

      assert text_chunks.any?
      assert_equal 1, response_chunks.size
      assert_equal response_chunks.first.data, response.data
    end
  end

  test "chat response with function calls" do
    VCR.use_cassette("ollama/chat/function_calls") do
      prompt = "What is my net worth?"

      functions = [
        {
          name: "get_net_worth",
          description: "Gets a user's net worth",
          params_schema: { type: "object", properties: {}, required: [], additionalProperties: false },
          strict: true
        }
      ]

      first_response = @subject.chat_response(
        prompt,
        model: @subject_model,
        instructions: "Use the tools available to you to answer the user's question.",
        functions: functions
      )

      assert first_response.success?

      # Ollama may or may not return function calls depending on model capabilities
      # This test verifies the interface works correctly
      if first_response.data.function_requests.any?
        function_request = first_response.data.function_requests.first

        second_response = @subject.chat_response(
          prompt,
          model: @subject_model,
          function_results: [ {
            call_id: function_request.call_id,
            output: { amount: 10000, currency: "USD" }.to_json
          } ]
        )

        assert second_response.success?
      end
    end
  end

  test "rejects too many transactions for auto_categorize" do
    transactions = (1..26).map { |i| { id: i.to_s, name: "Transaction #{i}", amount: 10, classification: "expense" } }

    response = @subject.auto_categorize(transactions: transactions, user_categories: [])

    assert_not response.success?
    assert_kind_of Provider::Ollama::Error, response.error
  end

  test "rejects too many transactions for auto_detect_merchants" do
    transactions = (1..26).map { |i| { id: i.to_s, name: "Transaction #{i}", amount: 10, classification: "expense" } }

    response = @subject.auto_detect_merchants(transactions: transactions, user_merchants: [])

    assert_not response.success?
    assert_kind_of Provider::Ollama::Error, response.error
  end
end
