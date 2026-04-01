class AddStartDatesToAccountTypes < ActiveRecord::Migration[7.2]
  def change
    # Loan - add start_date for when the loan was originated
    # Note: maturity_date, effective_interest_rate, fixed_rate_end_date, extra_payment_allowance_percent
    # may already exist from previous migrations - only add if they don't exist
    add_column :loans, :start_date, :date unless column_exists?(:loans, :start_date)
    add_column :loans, :maturity_date, :date unless column_exists?(:loans, :maturity_date)
    add_column :loans, :effective_interest_rate, :decimal, precision: 10, scale: 3 unless column_exists?(:loans, :effective_interest_rate)
    add_column :loans, :fixed_rate_end_date, :date unless column_exists?(:loans, :fixed_rate_end_date)
    add_column :loans, :extra_payment_allowance_percent, :decimal, precision: 5, scale: 2 unless column_exists?(:loans, :extra_payment_allowance_percent)

    # OtherLiability - add start_date and interest_rate for tracking debts
    add_column :other_liabilities, :start_date, :date
    add_column :other_liabilities, :interest_rate, :decimal, precision: 10, scale: 3

    # CreditCard - add opening_date for when the card was opened
    add_column :credit_cards, :opening_date, :date

    # Vehicle - add purchase_date for when the vehicle was bought
    add_column :vehicles, :purchase_date, :date

    # OtherAsset - add acquisition_date for when the asset was acquired
    add_column :other_assets, :acquisition_date, :date
    add_column :other_assets, :expected_growth_rate, :decimal, precision: 10, scale: 3

    # Depository - add opening_date for when the account was opened
    add_column :depositories, :opening_date, :date

    # Investment - add opening_date for when the account was opened
    add_column :investments, :opening_date, :date

    # Crypto - add acquisition_date for when crypto was first acquired
    add_column :cryptos, :acquisition_date, :date
    add_column :cryptos, :expected_growth_rate, :decimal, precision: 10, scale: 3

    # Note: Insurance start_date is now part of the create_insurances migration
  end
end
