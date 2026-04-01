require "test_helper"

class AccountPersonTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @bob = persons(:bob_person)
    @sara = persons(:sara_person)
  end

  test "for_person scope includes household accounts" do
    account = @family.accounts.first
    account.update!(ownership_type: "household")
    account.account_persons.destroy_all

    results = @family.accounts.for_person(@bob)
    assert_includes results, account
  end

  test "for_person scope includes personal accounts for that person" do
    account = @family.accounts.first
    account.update!(ownership_type: "personal")
    account.account_persons.destroy_all
    account.account_persons.create!(person: @bob)

    results = @family.accounts.for_person(@bob)
    assert_includes results, account

    results_sara = @family.accounts.for_person(@sara)
    assert_not_includes results_sara, account
  end

  test "for_person scope includes joint accounts for that person" do
    account = @family.accounts.first
    account.update!(ownership_type: "joint")
    account.account_persons.destroy_all
    account.account_persons.create!(person: @bob)
    account.account_persons.create!(person: @sara)

    assert_includes @family.accounts.for_person(@bob), account
    assert_includes @family.accounts.for_person(@sara), account
  end

  test "uniqueness of person per account" do
    account = @family.accounts.first
    account.account_persons.destroy_all
    account.account_persons.create!(person: @bob)

    duplicate = account.account_persons.build(person: @bob)
    assert_not duplicate.valid?
  end
end
