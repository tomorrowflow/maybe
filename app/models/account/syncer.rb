class Account::Syncer
  attr_reader :account

  def initialize(account)
    @account = account
  end

  def perform_sync(sync)
    Rails.logger.info("Processing balances (#{account.linked? ? 'reverse' : 'forward'})")
    import_market_data

    # For properties with HPI projection, generate quarterly valuations first
    if uses_hpi_projection?
      generate_hpi_valuations
    end

    # Run normal balance materialization (which will use the HPI valuations for properties)
    materialize_balances
  end

  def perform_post_sync
    account.family.auto_match_transfers!
  end

  private
    def uses_hpi_projection?
      account.property? && account.accountable.uses_hpi_projection?
    end

    def generate_hpi_valuations
      Rails.logger.info("Generating HPI valuations for property")
      account.accountable.generate_hpi_valuations
    end

    def materialize_balances
      strategy = account.linked? ? :reverse : :forward
      Balance::Materializer.new(account, strategy: strategy).materialize_balances
    end

    # Syncs all the exchange rates + security prices this account needs to display historical chart data
    #
    # This is a *supplemental* sync.  The daily market data sync should have already populated
    # a majority or all of this data, so this is often a no-op.
    #
    # We rescue errors here because if this operation fails, we don't want to fail the entire sync since
    # we have reasonable fallbacks for missing market data.
    def import_market_data
      Account::MarketDataImporter.new(account).import_all
    rescue => e
      Rails.logger.error("Error syncing market data for account #{account.id}: #{e.message}")
      Sentry.capture_exception(e)
    end
end
