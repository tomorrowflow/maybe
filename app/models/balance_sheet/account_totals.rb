class BalanceSheet::AccountTotals
  def initialize(family, sync_status_monitor:, person: nil)
    @family = family
    @sync_status_monitor = sync_status_monitor
    @person = person
  end

  def asset_accounts
    @asset_accounts ||= account_rows.filter { |t| t.classification == "asset" }
  end

  def liability_accounts
    @liability_accounts ||= account_rows.filter { |t| t.classification == "liability" }
  end

  private
    attr_reader :family, :sync_status_monitor, :person

    AccountRow = Data.define(:account, :converted_balance, :is_syncing) do
      def syncing? = is_syncing

      # Allows Rails path helpers to generate URLs from the wrapper
      def to_param = account.to_param
      delegate_missing_to :account
    end

    def visible_accounts
      @visible_accounts ||= begin
        scope = family.accounts.visible.with_attached_logo
        scope = scope.for_person(person) if person.present?
        scope
      end
    end

    def account_rows
      @account_rows ||= query.map do |account_row|
        AccountRow.new(
          account: account_row,
          converted_balance: account_row.converted_balance,
          is_syncing: sync_status_monitor.account_syncing?(account_row)
        )
      end
    end

    def cache_key
      key = person.present? ? "balance_sheet_account_rows_person_#{person.id}" : "balance_sheet_account_rows"
      family.build_cache_key(key, invalidate_on_data_updates: true)
    end

    def query
      @query ||= Rails.cache.fetch(cache_key) do
        visible_accounts
          .joins(ActiveRecord::Base.sanitize_sql_array([
            "LEFT JOIN exchange_rates ON exchange_rates.date = ? AND accounts.currency = exchange_rates.from_currency AND exchange_rates.to_currency = ?",
            Date.current,
            family.currency
          ]))
          .select(
            "accounts.*",
            "SUM(accounts.balance * COALESCE(exchange_rates.rate, 1)) as converted_balance"
          )
          .group(:classification, :accountable_type, :id)
          .to_a
      end
    end
end
