require "test_helper"

class Symphony::ConfigTest < ActiveSupport::TestCase
  test "resolves environment variables" do
    ENV["SYMPHONY_TEST_ACCOUNT"] = "1234567"

    config = Symphony::Config.new({ "tracker" => { "account_id" => "$SYMPHONY_TEST_ACCOUNT" } })

    assert_equal "1234567", config.tracker_account_id
  ensure
    ENV.delete("SYMPHONY_TEST_ACCOUNT")
  end

  test "includes active and merging in default active states" do
    config = Symphony::Config.new({ "tracker" => { "account_id" => "1234567" } })

    assert_equal [ "active", "merging" ], config.tracker_active_states
  end

  test "defaults active column names to todo, rework, and merging" do
    config = Symphony::Config.new({ "tracker" => { "account_id" => "1234567" } })

    assert_equal [ "Todo", "Rework", "Merging" ], config.tracker_active_column_names
  end

  test "includes done in default terminal states" do
    config = Symphony::Config.new({ "tracker" => { "account_id" => "1234567" } })

    assert_equal [ "closed", "not_now", "done" ], config.tracker_terminal_states
  end

  test "does not require tracker board ids" do
    config = Symphony::Config.new({ "tracker" => { "account_id" => "1234567" } })

    assert_nil config.tracker_board_ids
  end

  test "ignores blank tracker board ids" do
    config = Symphony::Config.new({
      "tracker" => {
        "account_id" => "1234567",
        "board_ids" => [ "", "  ", "board-123" ]
      }
    })

    assert_equal [ "board-123" ], config.tracker_board_ids
  end

  test "normalizes tracker states" do
    config = Symphony::Config.new({
      "tracker" => {
        "account_id" => "1234567",
        "active_states" => [ " active ", "", "REVIEW" ],
        "terminal_states" => [ " done ", "  ", "CLOSED" ]
      }
    })

    assert_equal [ "active", "review" ], config.tracker_active_states
    assert_equal [ "done", "closed" ], config.tracker_terminal_states
  end

  test "normalizes active column names" do
    config = Symphony::Config.new({
      "tracker" => {
        "account_id" => "1234567",
        "active_column_names" => [ " To do ", "", "In Progress" ]
      }
    })

    assert_equal [ "To do", "In Progress" ], config.tracker_active_column_names
  end

  test "ignores blank active column names" do
    config = Symphony::Config.new({
      "tracker" => {
        "account_id" => "1234567",
        "active_column_names" => [ "", "  " ]
      }
    })

    assert_nil config.tracker_active_column_names
  end


  test "uses telemetry log path default" do
    config = Symphony::Config.new({
      "tracker" => { "account_id" => "1234567" },
      "github" => { "repo" => "mmajdan/fizzy" }
    })

    assert_equal Pathname(File.join(Dir.tmpdir, "symphony_workspaces", "telemetry.log")).expand_path, config.telemetry_log_path
  end

  test "resolves telemetry log path from environment" do
    ENV["SYMPHONY_TEST_TELEMETRY_LOG_PATH"] = "/tmp/custom-telemetry.log"
    config = Symphony::Config.new({
      "tracker" => { "account_id" => "1234567" },
      "github" => { "repo" => "mmajdan/fizzy" },
      "telemetry" => { "log_path" => "$SYMPHONY_TEST_TELEMETRY_LOG_PATH" }
    })

    assert_equal Pathname("/tmp/custom-telemetry.log").expand_path, config.telemetry_log_path
  ensure
    ENV.delete("SYMPHONY_TEST_TELEMETRY_LOG_PATH")
  end

  test "falls back to default telemetry log path when env-backed override is unset" do
    ENV.delete("SYMPHONY_TEST_TELEMETRY_LOG_PATH")

    config = Symphony::Config.new({
      "tracker" => { "account_id" => "1234567" },
      "github" => { "repo" => "mmajdan/fizzy" },
      "telemetry" => { "log_path" => "$SYMPHONY_TEST_TELEMETRY_LOG_PATH" }
    })

    assert_equal Pathname(File.join(Dir.tmpdir, "symphony_workspaces", "telemetry.log")).expand_path, config.telemetry_log_path
  end

  test "requires fizzy account id" do
    config = Symphony::Config.new({})

    error = assert_raises(Symphony::ConfigurationError) { config.validate! }

    assert_match "tracker.account_id", error.message
  end

  test "requires github repo" do
    config = Symphony::Config.new({
      "tracker" => { "account_id" => "1234567" }
    })

    error = assert_raises(Symphony::ConfigurationError) { config.validate! }

    assert_match "github.repo", error.message
  end

  test "rejects codex app server command" do
    config = Symphony::Config.new({
      "tracker" => { "account_id" => "1234567" },
      "github" => { "repo" => "mmajdan/fizzy" },
      "runner" => { "command" => "codex app-server" }
    })

    error = assert_raises(Symphony::ConfigurationError) { config.validate! }

    assert_match "task executor", error.message
  end

  test "resolves runner base url from environment" do
    ENV["SYMPHONY_TEST_BASE_URL"] = "https://openai-compatible.example/v1"
    ENV["SYMPHONY_TEST_MODEL"] = "gpt-4.1-mini"
    ENV["SYMPHONY_TEST_API_KEY_ENV"] = "FIREWORKS_API_KEY"

    config = Symphony::Config.new({
      "tracker" => { "account_id" => "1234567" },
      "github" => { "repo" => "mmajdan/fizzy" },
      "runner" => {
        "base_url" => "$SYMPHONY_TEST_BASE_URL",
        "model" => "$SYMPHONY_TEST_MODEL",
        "api_key_env" => "$SYMPHONY_TEST_API_KEY_ENV"
      }
    })

    assert_equal "gpt-4.1-mini", config.runner_model
    assert_equal "https://openai-compatible.example/v1", config.runner_base_url
    assert_equal "login_then_api_key", config.runner_auth_strategy
    assert_equal "FIREWORKS_API_KEY", config.runner_api_key_env
    assert_equal "responses", config.runner_wire_api
    assert_equal "symphony_openai_compatible", config.runner_model_provider
  ensure
    ENV.delete("SYMPHONY_TEST_BASE_URL")
    ENV.delete("SYMPHONY_TEST_MODEL")
    ENV.delete("SYMPHONY_TEST_API_KEY_ENV")
  end

  test "supports literal runner api key" do
    config = Symphony::Config.new({
      "tracker" => { "account_id" => "1234567" },
      "github" => { "repo" => "mmajdan/fizzy" },
      "runner" => {
        "api_key" => "secret-123",
        "api_key_env" => "FIREWORKS_API_KEY"
      }
    })

    assert_equal "secret-123", config.runner_api_key
    assert_equal "FIREWORKS_API_KEY", config.runner_api_key_env
    assert config.validate!
  end

  test "accepts supported runner auth strategies" do
    %w[login_then_api_key login_only api_key_only].each do |strategy|
      config = Symphony::Config.new({
        "tracker" => { "account_id" => "1234567" },
        "github" => { "repo" => "mmajdan/fizzy" },
        "runner" => { "auth_strategy" => strategy }
      })

      assert_equal strategy, config.runner_auth_strategy
      assert config.validate!
    end
  end

  test "rejects unsupported runner auth strategy" do
    config = Symphony::Config.new({
      "tracker" => { "account_id" => "1234567" },
      "github" => { "repo" => "mmajdan/fizzy" },
      "runner" => { "auth_strategy" => "magic" }
    })

    error = assert_raises(Symphony::ConfigurationError) { config.validate! }

    assert_match "runner.auth_strategy", error.message
  end

  test "supports legacy codex keys as fallback" do
    config = Symphony::Config.new({
      "tracker" => { "account_id" => "1234567" },
      "github" => { "repo" => "mmajdan/fizzy" },
      "codex" => {
        "command" => "opencode run --format json",
        "auth_strategy" => "login_only",
        "model" => "openai/gpt-5.2",
        "api_key_env" => "CUSTOM_KEY"
      }
    })

    assert_equal "opencode run --format json", config.runner_command
    assert_equal "login_only", config.runner_auth_strategy
    assert_equal "openai/gpt-5.2", config.runner_model
    assert_equal "CUSTOM_KEY", config.runner_api_key_env
  end

  test "prefers runner keys over legacy codex keys" do
    config = Symphony::Config.new({
      "tracker" => { "account_id" => "1234567" },
      "github" => { "repo" => "mmajdan/fizzy" },
      "runner" => { "command" => "opencode run --format json" },
      "codex" => { "command" => "codex exec -" }
    })

    assert_equal "opencode run --format json", config.runner_command
  end

  test "falls back to runner defaults when env-backed runner values are unset" do
    config = Symphony::Config.new({
      "tracker" => { "account_id" => "1234567" },
      "github" => { "repo" => "mmajdan/fizzy" },
      "runner" => {
        "command" => "$RUNNER_COMMAND",
        "auth_strategy" => "$RUNNER_AUTH_STRATEGY"
      }
    })

    assert_equal "codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check -", config.runner_command
    assert_equal "login_then_api_key", config.runner_auth_strategy
  end

  test "reads github credentials" do
    ENV["SYMPHONY_GITHUB_TOKEN"] = "secret-token"

    config = Symphony::Config.new({
      "tracker" => { "account_id" => "1234567" },
      "github" => {
        "repo" => "mmajdan/fizzy",
        "username" => "mmajdan",
        "token_env" => "$SYMPHONY_GITHUB_TOKEN"
      }
    })

    assert_equal "mmajdan", config.github_username
    assert_equal "secret-token", config.github_token
  ensure
    ENV.delete("SYMPHONY_GITHUB_TOKEN")
  end
end
