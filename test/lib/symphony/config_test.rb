require "test_helper"

class Symphony::ConfigTest < ActiveSupport::TestCase
  test "resolves environment variables" do
    ENV["SYMPHONY_TEST_ACCOUNT"] = "1234567"

    config = Symphony::Config.new({ "tracker" => { "account_id" => "$SYMPHONY_TEST_ACCOUNT" } })

    assert_equal "1234567", config.tracker_account_id
  ensure
    ENV.delete("SYMPHONY_TEST_ACCOUNT")
  end

  test "requires fizzy account id" do
    config = Symphony::Config.new({})

    error = assert_raises(Symphony::ConfigurationError) { config.validate! }

    assert_match "tracker.account_id", error.message
  end
end
