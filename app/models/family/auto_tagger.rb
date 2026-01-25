class Family::AutoTagger
  Error = Class.new(StandardError)

  def initialize(family, transaction_ids: [])
    @family = family
    @transaction_ids = transaction_ids
  end

  def auto_tag
    if scope.none?
      Rails.logger.info("No transactions to auto-tag for family #{family.id}")
      return
    end

    Rails.logger.info("Auto-tagging #{scope.count} transactions for family #{family.id}")

    # First pass: try keyword matching (fast, free)
    remaining_transactions = tag_with_keywords

    # Second pass: use AI for remaining transactions
    if remaining_transactions.any? && llm_provider
      tag_with_ai(remaining_transactions)
    elsif remaining_transactions.any?
      Rails.logger.info("No LLM provider available, #{remaining_transactions.count} transactions left without tags")
    end
  end

  private
    attr_reader :family, :transaction_ids

    def tag_with_keywords
      remaining = []

      scope.each do |transaction|
        tags = TagKeyword.match_tags(family, transaction.entry.name)

        if tags.any?
          Rails.logger.info("Tagged transaction #{transaction.id} with #{tags.map(&:name).join(', ')} via keywords")
          transaction.tags = (transaction.tags + tags).uniq
          transaction.save!
        else
          remaining << transaction
        end
      end

      Rails.logger.info("Keyword-based tagging: #{scope.count - remaining.count} matched, #{remaining.count} remaining for AI")
      remaining
    end

    def tag_with_ai(transactions)
      Rails.logger.info("Using AI to tag #{transactions.count} transactions")

      # Process in batches of 25 (provider limit)
      transactions.each_slice(25) do |batch|
        ai_transactions_input = batch.map do |transaction|
          {
            id: transaction.id,
            amount: transaction.entry.amount.abs,
            classification: transaction.entry.classification,
            description: transaction.entry.name,
            merchant: transaction.merchant&.name,
            category: transaction.category&.name
          }
        end

        result = llm_provider.auto_tag(
          transactions: ai_transactions_input,
          user_tags: user_tags_input
        )

        unless result.success?
          Rails.logger.error("Failed to auto-tag batch for family #{family.id}: #{result.error.message}")
          next
        end

        batch.each do |transaction|
          auto_tagging = result.data.find { |t| t.transaction_id == transaction.id }
          next unless auto_tagging&.tag_names&.any?

          tags = auto_tagging.tag_names.map do |tag_name|
            family.tags.find_or_create_by!(name: tag_name)
          end

          transaction.tags = (transaction.tags + tags).uniq
          transaction.save!
        end

        Rails.logger.info("Tagged batch of #{batch.count} transactions")
      end
    end

    # Try OpenAI first, fall back to Ollama for self-hosted deployments
    def llm_provider
      provider = Provider::Registry.get_provider(:openai) || Provider::Registry.get_provider(:ollama)
      # Only return provider if it supports auto_tag
      provider if provider&.respond_to?(:auto_tag)
    end

    def user_tags_input
      @user_tags_input ||= family.tags.map do |tag|
        { id: tag.id, name: tag.name }
      end
    end

    def scope
      @scope ||= family.transactions.where(id: transaction_ids)
                       .includes(:tags, :category, :merchant, :entry)
    end
end
