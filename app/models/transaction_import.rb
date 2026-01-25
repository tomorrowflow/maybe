class TransactionImport < Import
  def import!
    # Check upfront if any mappings have auto_ai enabled
    has_category_auto_ai = mappings.categories.auto_ai.any?
    has_tag_auto_ai = mappings.tags.auto_ai.any?

    transaction do
      mappings.each(&:create_mappable!)

      transactions = rows.map do |row|
        mapped_account = if account
          account
        else
          mappings.accounts.mappable_for(row.account)
        end

        # Check if this specific category mapping uses AI
        category_mapping = mappings.categories.find_by(key: row.category)
        use_ai_for_category = category_mapping&.auto_ai?
        category = use_ai_for_category ? nil : mappings.categories.mappable_for(row.category)

        # Check if any tag mappings use AI
        tags = row.tags_list.map do |tag|
          tag_mapping = mappings.tags.find_by(key: tag)
          if tag_mapping&.auto_ai?
            nil
          else
            mappings.tags.mappable_for(tag)
          end
        end.compact

        Transaction.new(
          category: category,
          tags: tags,
          entry: Entry.new(
            account: mapped_account,
            date: row.date_iso,
            amount: row.signed_amount,
            name: row.name,
            currency: row.currency,
            notes: row.notes,
            import: self
          )
        )
      end

      Transaction.import!(transactions, recursive: true)
    end

    # After import completes, queue AI jobs for uncategorized/untagged transactions
    if has_category_auto_ai
      uncategorized_transactions = family.transactions
        .joins(:entry)
        .where(entries: { import_id: id })
        .where(category_id: nil)

      if uncategorized_transactions.any?
        Rails.logger.info("Queuing AI categorization for #{uncategorized_transactions.count} transactions from import #{id}")
        family.auto_categorize_transactions_later(uncategorized_transactions)
      end
    end

    if has_tag_auto_ai
      # Find transactions from this import that have no tags
      untagged_transactions = family.transactions
        .joins(:entry)
        .where(entries: { import_id: id })
        .left_joins(:taggings)
        .where(taggings: { id: nil })

      if untagged_transactions.any?
        Rails.logger.info("Queuing AI tagging for #{untagged_transactions.count} transactions from import #{id}")
        family.auto_tag_transactions_later(untagged_transactions)
      end
    end
  end

  def required_column_keys
    %i[date amount]
  end

  def column_keys
    base = %i[date amount name currency category tags notes]
    base.unshift(:account) if account.nil?
    base
  end

  def mapping_steps
    base = [ Import::CategoryMapping, Import::TagMapping ]
    base << Import::AccountMapping if account.nil?
    base
  end

  def selectable_amount_type_values
    return [] if entity_type_col_label.nil?

    csv_rows.map { |row| row[entity_type_col_label] }.uniq
  end

  def csv_template
    template = <<-CSV
      date*,amount*,name,currency,category,tags,account,notes
      05/15/2024,-45.99,Grocery Store,USD,Food,groceries|essentials,Checking Account,Monthly grocery run
      05/16/2024,1500.00,Salary,,Income,,Main Account,
      05/17/2024,-12.50,Coffee Shop,,,coffee,,
    CSV

    csv = CSV.parse(template, headers: true)
    csv.delete("account") if account.present?
    csv
  end
end
