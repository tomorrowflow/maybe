class AddInterestOnlyToLoans < ActiveRecord::Migration[7.2]
  def change
    add_column :loans, :interest_only, :boolean, default: false
  end
end
