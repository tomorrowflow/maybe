class RetirementScenario
  class CashFlowAnalyzer
    attr_reader :family, :year

    def initialize(family, year: nil)
      @family = family
      @year = year || default_year
    end

    def analyze
      {
        year: year,
        available_years: available_years,
        annual_income: annual_income,
        annual_expenses: annual_expenses,
        monthly_income: (annual_income / 12.0).round(2),
        monthly_expenses: (annual_expenses / 12.0).round(2),
        net_annual: annual_income - annual_expenses,
        recurring_payments: detect_recurring_payments,
        uncategorized_count: uncategorized_count,
        income_by_category: income_by_category,
        expenses_by_category: expenses_by_category
      }
    end

    def available_years
      @available_years ||= begin
        min_date = family_entries.minimum(:date)
        max_date = family_entries.maximum(:date)
        return [] unless min_date && max_date
        (min_date.year..max_date.year).to_a.reverse
      end
    end

    private

      def default_year
        Date.today.year - 1
      end

      def year_range
        Date.new(year, 1, 1)..Date.new(year, 12, 31)
      end

      def account_ids
        @account_ids ||= family.accounts.active.pluck(:id)
      end

      def family_entries
        Entry.where(account_id: account_ids)
      end

      def year_transaction_entries
        @year_transaction_entries ||= family_entries
          .where(entryable_type: "Transaction", date: year_range)
      end

      # Income = negative amounts (inflows)
      def annual_income
        @annual_income ||= year_transaction_entries
          .joins("JOIN transactions t ON t.id = entries.entryable_id")
          .where("t.kind = 'standard'")
          .where("entries.amount < 0")
          .sum(:amount).abs.to_f
      end

      # Expenses = positive amounts (outflows)
      def annual_expenses
        @annual_expenses ||= year_transaction_entries
          .joins("JOIN transactions t ON t.id = entries.entryable_id")
          .where("t.kind = 'standard'")
          .where("entries.amount > 0")
          .sum(:amount).to_f
      end

      def income_by_category
        year_transaction_entries
          .joins("JOIN transactions t ON t.id = entries.entryable_id")
          .joins("LEFT JOIN categories c ON c.id = t.category_id")
          .where("t.kind = 'standard'")
          .where("entries.amount < 0")
          .group("COALESCE(c.name, 'Uncategorized')")
          .sum("ABS(entries.amount)")
          .transform_values(&:to_f)
          .sort_by { |_, v| -v }
      end

      def expenses_by_category
        year_transaction_entries
          .joins("JOIN transactions t ON t.id = entries.entryable_id")
          .joins("LEFT JOIN categories c ON c.id = t.category_id")
          .where("t.kind = 'standard'")
          .where("entries.amount > 0")
          .group("COALESCE(c.name, 'Uncategorized')")
          .sum(:amount)
          .transform_values(&:to_f)
          .sort_by { |_, v| -v }
      end

      def uncategorized_count
        year_transaction_entries
          .joins("JOIN transactions t ON t.id = entries.entryable_id")
          .where("t.category_id IS NULL")
          .where("t.kind = 'standard'")
          .count
      end

      # Detect recurring expense payments (3+ occurrences in the year)
      def detect_recurring_payments
        sql = <<~SQL
          SELECT e.name,
                 COUNT(*) as occurrences,
                 AVG(e.amount) as avg_amount,
                 STDDEV(e.amount) as stddev_amount,
                 MIN(e.date) as first_date,
                 MAX(e.date) as last_date
          FROM entries e
          JOIN transactions t ON t.id = e.entryable_id AND e.entryable_type = 'Transaction'
          WHERE e.account_id IN (#{account_ids.map { |id| ActiveRecord::Base.connection.quote(id) }.join(",")})
            AND e.amount > 0
            AND e.date BETWEEN #{ActiveRecord::Base.connection.quote(year_range.first)} AND #{ActiveRecord::Base.connection.quote(year_range.last)}
            AND t.kind IN ('standard', 'funds_movement')
          GROUP BY e.name
          HAVING COUNT(*) >= 3
          ORDER BY AVG(e.amount) DESC
        SQL

        return [] if account_ids.empty?

        results = ActiveRecord::Base.connection.execute(sql)
        linkable_accounts = build_linkable_accounts

        results.map do |row|
          avg = row["avg_amount"].to_f
          stddev = row["stddev_amount"].to_f
          stable = stddev < avg * 0.15  # within 15% variance

          suggested = find_matching_account(row["name"], avg, linkable_accounts)

          {
            name: row["name"],
            occurrences: row["occurrences"].to_i,
            avg_amount: avg.round(2),
            monthly_amount: (avg).round(2),
            stable: stable,
            first_date: row["first_date"],
            last_date: row["last_date"],
            suggested_account_id: suggested&.dig(:account_id),
            suggested_account_name: suggested&.dig(:account_name),
            confidence: suggested&.dig(:confidence)
          }
        end
      end

      # Build a list of accounts that could be targets for recurring payment linking
      def build_linkable_accounts
        accounts = []

        family.accounts.active.where(accountable_type: "Loan").includes(:accountable).each do |a|
          loan = a.accountable
          payment = loan.respond_to?(:monthly_payment) ? loan.monthly_payment : nil
          payment = payment.is_a?(Money) ? payment.amount.to_f : payment.to_f if payment
          accounts << { account_id: a.id, account_name: a.name, type: :loan, monthly_amount: payment, keywords: extract_keywords(a.name) }
        end

        family.accounts.active.where(accountable_type: "BausparContract").includes(:accountable).each do |a|
          bauspar = a.accountable
          contribution = bauspar.monthly_contribution
          contribution = contribution.is_a?(Money) ? contribution.amount.to_f : contribution.to_f if contribution
          accounts << { account_id: a.id, account_name: a.name, type: :bauspar, monthly_amount: contribution, keywords: extract_keywords(a.name) }
        end

        family.accounts.active.where(accountable_type: "Investment").includes(:accountable).each do |a|
          accounts << { account_id: a.id, account_name: a.name, type: :investment, monthly_amount: nil, keywords: extract_keywords(a.name) }
        end

        family.accounts.active.where(accountable_type: "Insurance").includes(:accountable).each do |a|
          accounts << { account_id: a.id, account_name: a.name, type: :insurance, monthly_amount: nil, keywords: extract_keywords(a.name) }
        end

        family.accounts.active.where(accountable_type: "PrivateLoan").includes(:accountable).each do |a|
          loan = a.accountable
          payment = loan.respond_to?(:monthly_payment) ? loan.monthly_payment : nil
          payment = payment.is_a?(Money) ? payment.amount.to_f : payment.to_f if payment
          accounts << { account_id: a.id, account_name: a.name, type: :private_loan, monthly_amount: payment, keywords: extract_keywords(a.name) }
        end

        accounts
      end

      # Try to match a transaction name to a known account
      def find_matching_account(txn_name, txn_amount, accounts)
        txn_keywords = extract_keywords(txn_name)
        best_match = nil
        best_score = 0

        accounts.each do |account|
          score = 0

          # Keyword overlap
          common = (txn_keywords & account[:keywords])
          score += common.size * 2 if common.any?

          # Amount match (within 5%)
          if account[:monthly_amount] && account[:monthly_amount] > 0
            diff = (txn_amount - account[:monthly_amount]).abs
            if diff < account[:monthly_amount] * 0.05
              score += 3  # Strong signal
            elsif diff < account[:monthly_amount] * 0.15
              score += 1
            end
          end

          # Known patterns
          score += 2 if txn_name.downcase.include?("bausparkasse") && account[:type] == :bauspar
          score += 2 if txn_name.downcase.match?(/versicherung|lebensvers/) && account[:type].in?([ :insurance, :investment ])
          score += 2 if txn_name.downcase.include?("volksbank") && account[:type] == :loan

          if score > best_score
            best_score = score
            confidence = score >= 5 ? :high : (score >= 3 ? :medium : :low)
            best_match = { account_id: account[:account_id], account_name: account[:account_name], confidence: confidence }
          end
        end

        best_match if best_score >= 2
      end

      def extract_keywords(name)
        name.to_s.downcase
            .gsub(/[^a-zäöüß\s]/, "")
            .split(/\s+/)
            .reject { |w| w.length < 3 }
            .uniq
      end
  end
end
