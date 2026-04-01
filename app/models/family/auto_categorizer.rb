class Family::AutoCategorizer
  include AiProcessable

  Error = Class.new(StandardError)

  def initialize(family, transaction_ids: [])
    @family = family
    @transaction_ids = transaction_ids
  end

  def auto_categorize
    if scope.none?
      Rails.logger.info("No transactions to auto-categorize for family #{family.id}")
      return
    end

    total = scope.count
    Rails.logger.info("Auto-categorizing #{total} transactions for family #{family.id}")
    init_progress(total)

    # First pass: try keyword and MCC matching (fast, free)
    remaining_transactions = categorize_with_rules

    rule_matched = total - remaining_transactions.count
    update_progress(processed: rule_matched, rule_matched: rule_matched)

    # Second pass: use AI for remaining transactions
    if remaining_transactions.any? && llm_provider
      categorize_with_ai(remaining_transactions, rule_matched: rule_matched)
    elsif remaining_transactions.any?
      Rails.logger.info("No LLM provider available, #{remaining_transactions.count} transactions left uncategorized")
      remaining_transactions.each { |t| t.lock_attr!(:category_id) }
    end

    complete_progress
  end

  private
    attr_reader :family, :transaction_ids

    def job_type
      "auto_categorize"
    end

    def categorize_with_rules
      remaining = []

      scope.each do |transaction|
        category = nil
        source = nil

        # Try keyword matching first
        category = CategoryKeyword.match_category(family, transaction.entry.name)
        source = "keyword" if category

        # Try MCC code matching if no keyword match and MCC codes are loaded
        if category.nil? && MccCode.any?
          mcc_hint = MccCode.suggest_category(extract_mcc(transaction))
          if mcc_hint
            category = family.categories.find_by(name: mcc_hint)
            source = "mcc" if category
          end
        end

        if category
          Rails.logger.info("Categorized transaction #{transaction.id} as '#{category.name}' via #{source}")
          transaction.enrich_attribute(:category_id, category.id, source: source)
          transaction.lock_attr!(:category_id)
        else
          remaining << transaction
        end
      end

      Rails.logger.info("Rule-based categorization: #{scope.count - remaining.count} matched, #{remaining.count} remaining for AI")
      remaining
    end

    def categorize_with_ai(transactions, rule_matched:)
      Rails.logger.info("Using AI to categorize #{transactions.count} transactions")

      ai_processed = 0

      # Process in batches of 25 (provider limit)
      transactions.each_slice(25) do |batch|
        ai_transactions_input = batch.map do |transaction|
          {
            id: transaction.id,
            amount: transaction.entry.amount.abs,
            classification: transaction.entry.classification,
            description: transaction.entry.name,
            merchant: transaction.merchant&.name
          }
        end

        result = llm_provider.auto_categorize(
          transactions: ai_transactions_input,
          user_categories: user_categories_input
        )

        unless result.success?
          Rails.logger.error("Failed to auto-categorize batch for family #{family.id}: #{result.error.message}")
          batch.each { |t| t.lock_attr!(:category_id) }
          ai_processed += batch.size
          update_progress(processed: rule_matched + ai_processed, ai_processed: ai_processed)
          next
        end

        batch.each do |transaction|
          auto_categorization = result.data.find { |c| c.transaction_id == transaction.id }
          category_id = user_categories_input.find { |c| c[:name] == auto_categorization&.category_name }&.dig(:id)

          if category_id.present?
            transaction.enrich_attribute(:category_id, category_id, source: "ai")
          end

          transaction.lock_attr!(:category_id)
        end

        ai_processed += batch.size
        update_progress(processed: rule_matched + ai_processed, ai_processed: ai_processed)
        Rails.logger.info("Categorized batch of #{batch.count} transactions")
      end
    end

    def extract_mcc(transaction)
      # MCC codes are typically embedded in transaction metadata from bank feeds
      # For now, return nil - MCC matching can be implemented when bank data includes MCC
      nil
    end

    # Try OpenAI first, fall back to Ollama for self-hosted deployments
    def llm_provider
      Provider::Registry.get_provider(:openai) || Provider::Registry.get_provider(:ollama)
    end

    def user_categories_input
      @user_categories_input ||= family.categories.map do |category|
        {
          id: category.id,
          name: category.name,
          is_subcategory: category.subcategory?,
          parent_id: category.parent_id,
          classification: category.classification
        }
      end
    end

    def scope
      @scope ||= family.transactions.where(id: transaction_ids, category_id: nil)
                       .enrichable(:category_id)
                       .includes(:category, :merchant, :entry)
    end
end
