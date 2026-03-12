require "test_helper"

class Symphony::ConfigTest < ActiveSupport::TestCase
  test "resolves environment variables" do
    ENV["SYMPHONY_TEST_ACCOUNT"] = "1234567"

    config = Symphony::Config.new({ "tracker" => { "account_id" => "$SYMPHONY_TEST_ACCOUNT" } })

    assert_equal "1234567", config.tracker_account_id
  ensure
    ENV.delete("SYMPHONY_TEST_ACCOUNT")
  end

  test "only includes active in default active states" do
    config = Symphony::Config.new({ "tracker" => { "account_id" => "1234567" } })

    assert_equal [ "active" ], config.tracker_active_states
  end

  test "includes done in default terminal states" do
    config = Symphony::Config.new({ "tracker" => { "account_id" => "1234567" } })

    assert_equal [ "closed", "not_now", "done" ], config.tracker_terminal_states
  end

  test "does not require tracker board ids" do
    config = Symphony::Config.new({ "tracker" => { "account_id" => "1234567" } })

    assert_nil config.tracker_board_ids
  end

  test "requires fizzy account id" do
    config = Symphony::Config.new({})

    error = assert_raises(Symphony::ConfigurationError) { config.validate! }

    assert_match "tracker.account_id", error.message
  end

  test "rejects codex app server command" do
    config = Symphony::Config.new({
      "tracker" => { "account_id" => "1234567" },
      "codex" => { "command" => "codex app-server" }
    })

    error = assert_raises(Symphony::ConfigurationError) { config.validate! }

    assert_match "task executor", error.message
  end
end
