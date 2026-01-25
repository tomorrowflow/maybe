namespace :categories do
  desc "Import expanded category set (German banking style categories)"
  task :import_expanded, [ :family_id ] => :environment do |_t, args|
    family = if args[:family_id]
      Family.find(args[:family_id])
    else
      Family.first
    end

    unless family
      puts "No family found. Please specify a family_id or ensure at least one family exists."
      exit 1
    end

    puts "Importing expanded categories for family: #{family.id}"

    # Define the expanded category structure
    # Format: [name, color, icon, classification, subcategories]
    expanded_categories = [
      {
        name: "Finances & Insurances",
        color: "#6471eb",
        icon: "credit-card",
        classification: "expense",
        subcategories: [
          "Insurances",
          "Interest & Investments",
          "Real Estate",
          "Transfer",
          "Wage & Salary",
          "ATM",
          "Bank Charges",
          "Job & Business",
          "Savings",
          "Services",
          "Child Allowance & Alimony",
          "Credits & Financing"
        ]
      },
      {
        name: "Leisure & Entertainment",
        color: "#df4e92",
        icon: "drama",
        classification: "expense",
        subcategories: [
          "Trips & Activities",
          "Media",
          "Lottery",
          "Vacation",
          "Arts & Culture",
          "Associations",
          "Sports",
          "Streaming",
          "Hobby"
        ]
      },
      {
        name: "Living",
        color: "#4da568",
        icon: "house",
        classification: "expense",
        subcategories: [
          "Shopping",
          "Groceries",
          "Rent & Utilities",
          "Home Improvement",
          "Furniture",
          "Healthcare",
          "Personal Care",
          "Food & Drink",
          "Clothing"
        ]
      },
      {
        name: "Mobility",
        color: "#61c9ea",
        icon: "bus",
        classification: "expense",
        subcategories: [
          "Gas & Charging Station",
          "Car & Motorcycle",
          "Transport",
          "Bicycle & Scooter",
          "Parking",
          "Car Insurance",
          "Car Maintenance"
        ]
      },
      {
        name: "State & Authority",
        color: "#805dee",
        icon: "building",
        classification: "expense",
        subcategories: [
          "Social Benefits",
          "Taxes",
          "Office & Administration Costs",
          "Broadcasting Fee",
          "Fees & Fines"
        ]
      },
      {
        name: "Income",
        color: "#e99537",
        icon: "circle-dollar-sign",
        classification: "income",
        subcategories: [
          "Salary",
          "Bonus",
          "Investment Income",
          "Rental Income",
          "Side Income",
          "Refunds",
          "Gifts Received"
        ]
      }
    ]

    created_count = 0
    skipped_count = 0

    expanded_categories.each do |cat_data|
      # Create or find the parent category
      parent = family.categories.find_or_initialize_by(name: cat_data[:name])

      if parent.new_record?
        parent.color = cat_data[:color]
        parent.lucide_icon = cat_data[:icon]
        parent.classification = cat_data[:classification]
        parent.save!
        puts "  Created parent: #{parent.name}"
        created_count += 1
      else
        puts "  Skipped parent (exists): #{parent.name}"
        skipped_count += 1
      end

      # Create subcategories
      cat_data[:subcategories].each do |sub_name|
        sub = family.categories.find_or_initialize_by(name: sub_name)

        if sub.new_record?
          sub.parent = parent
          sub.color = parent.color
          sub.lucide_icon = parent.lucide_icon
          sub.classification = parent.classification
          sub.save!
          puts "    Created subcategory: #{sub_name}"
          created_count += 1
        else
          puts "    Skipped subcategory (exists): #{sub_name}"
          skipped_count += 1
        end
      end
    end

    puts ""
    puts "Import complete!"
    puts "  Created: #{created_count}"
    puts "  Skipped: #{skipped_count}"
  end

  desc "List all categories for a family"
  task :list, [ :family_id ] => :environment do |_t, args|
    family = if args[:family_id]
      Family.find(args[:family_id])
    else
      Family.first
    end

    unless family
      puts "No family found."
      exit 1
    end

    puts "Categories for family: #{family.id}"
    puts ""

    family.categories.roots.order(:classification, :name).each do |parent|
      puts "#{parent.classification.upcase}: #{parent.name} (#{parent.color})"
      parent.subcategories.order(:name).each do |sub|
        puts "  - #{sub.name}"
      end
    end
  end
end
