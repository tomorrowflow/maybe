class AccountPerson < ApplicationRecord
  belongs_to :account
  belongs_to :person

  validates :person_id, uniqueness: { scope: :account_id }
end
