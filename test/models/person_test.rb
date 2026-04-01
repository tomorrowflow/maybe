require "test_helper"

class PersonTest < ActiveSupport::TestCase
  setup do
    @person = persons(:bob_person)
    @family = families(:dylan_family)
  end

  test "requires first_name" do
    person = Person.new(family: @family)
    assert_not person.valid?
    assert_includes person.errors[:first_name], "can't be blank"
  end

  test "display_name combines first and last name" do
    assert_equal "Bob Dylan", @person.display_name
  end

  test "display_name works with only first name" do
    person = Person.new(first_name: "Alice")
    assert_equal "Alice", person.display_name
  end

  test "age calculates from date_of_birth" do
    person = Person.new(date_of_birth: 30.years.ago.to_date)
    assert_equal 30, person.age
  end

  test "age returns nil without date_of_birth" do
    person = Person.new
    assert_nil person.age
  end

  test "estimated_retirement_date calculates from birth and retirement_age" do
    person = Person.new(date_of_birth: Date.new(1965, 5, 24), retirement_age: 67)
    assert_equal Date.new(2032, 5, 24), person.estimated_retirement_date
  end

  test "estimated_retirement_date returns nil without required fields" do
    assert_nil Person.new(date_of_birth: Date.new(1965, 1, 1)).estimated_retirement_date
    assert_nil Person.new(retirement_age: 67).estimated_retirement_date
  end

  test "primary scope returns only primary persons" do
    primary = @family.persons.primary
    assert primary.all?(&:primary?)
  end

  test "family can ensure_primary_person" do
    family = families(:empty)
    user = users(:empty)
    person = family.ensure_primary_person!(user)
    assert person.primary?
    assert_equal user.first_name, person.first_name
  end

  test "ensure_primary_person returns existing primary person" do
    user = users(:family_admin)
    existing = @family.persons.find_by(primary: true)
    result = @family.ensure_primary_person!(user)
    assert_equal existing, result
  end
end
