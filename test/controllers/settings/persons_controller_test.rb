require "test_helper"

class Settings::PersonsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:family_admin)
    @member = users(:family_member)
    @person = persons(:sara_person)
  end

  test "can create a person" do
    sign_in @admin
    assert_difference("Person.count", 1) do
      post settings_persons_path, params: {
        person: { first_name: "Charlie", last_name: "Dylan", date_of_birth: "2000-01-01", retirement_age: 67, gender: "male", country: "US" }
      }
    end
    assert_redirected_to settings_profile_path
  end

  test "cannot create person without first_name" do
    sign_in @admin
    assert_no_difference("Person.count") do
      post settings_persons_path, params: {
        person: { last_name: "Dylan" }
      }
    end
    assert_redirected_to settings_profile_path
    assert flash[:alert].present?
  end

  test "can update a person" do
    sign_in @admin
    patch settings_person_path(@person), params: {
      person: { first_name: "Sara Jane" }
    }
    assert_redirected_to settings_profile_path
    assert_equal "Sara Jane", @person.reload.first_name
  end

  test "can destroy a non-primary person without a user" do
    sign_in @admin
    assert_difference("Person.count", -1) do
      delete settings_person_path(@person)
    end
    assert_redirected_to settings_profile_path
  end

  test "cannot destroy the primary person" do
    sign_in @admin
    primary = persons(:bob_person)
    assert_no_difference("Person.count") do
      delete settings_person_path(primary)
    end
    assert_redirected_to settings_profile_path
    assert_equal "Cannot remove the primary household member.", flash[:alert]
  end

  test "member can also manage persons" do
    sign_in @member
    assert_difference("Person.count", 1) do
      post settings_persons_path, params: {
        person: { first_name: "New", last_name: "Person" }
      }
    end
    assert_redirected_to settings_profile_path
  end
end
