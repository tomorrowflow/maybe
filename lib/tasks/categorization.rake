namespace :categorization do
  desc "Seed default category keywords for a family"
  task seed_keywords: :environment do
    Family.find_each do |family|
      puts "Seeding keywords for family: #{family.id}"
      CategoryKeyword.seed_defaults(family)
      puts "  Created #{family.category_keywords.count} keyword mappings"
    end
  end

  desc "Test auto-categorization on a sample transaction name"
  task :test, [ :transaction_name ] => :environment do |t, args|
    name = args[:transaction_name] || "AMAZON PURCHASE"
    puts "Testing categorization for: '#{name}'"
    puts "-" * 50

    Family.find_each do |family|
      puts "\nFamily: #{family.id}"

      # Test keyword matching
      category = CategoryKeyword.match_category(family, name)
      if category
        puts "  ✓ Keyword match: #{category.name}"
      else
        puts "  ✗ No keyword match"
      end

      # Test MCC matching (if codes loaded)
      if MccCode.any?
        puts "  MCC codes loaded: #{MccCode.count}"
      else
        puts "  ✗ No MCC codes loaded"
      end

      # Check LLM availability
      llm = Provider::Registry.get_provider(:openai) || Provider::Registry.get_provider(:ollama)
      if llm
        puts "  ✓ LLM available: #{llm.class.name}"
      else
        puts "  ✗ No LLM provider configured"
      end
    end
  end

  desc "Run auto-categorization on uncategorized transactions"
  task run: :environment do
    Family.find_each do |family|
      uncategorized = family.transactions.where(category_id: nil).limit(25)

      if uncategorized.none?
        puts "Family #{family.id}: No uncategorized transactions"
        next
      end

      puts "Family #{family.id}: Auto-categorizing #{uncategorized.count} transactions..."

      categorizer = Family::AutoCategorizer.new(family, transaction_ids: uncategorized.pluck(:id))
      categorizer.auto_categorize

      puts "  Done!"
    end
  end
end
