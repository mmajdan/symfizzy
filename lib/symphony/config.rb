require "tmpdir"

module Symphony
  class Config
    DEFAULTS = {
      "tracker" => {
        "kind" => "fizzy",
        "active_states" => [ "active" ],
        "terminal_states" => [ "closed", "not_now", "done" ]
      },
      "polling" => {
        "interval_ms" => 30_000
      },
      "workspace" => {
        "root" => File.join(Dir.tmpdir, "symphony_workspaces")
      },
      "agent" => {
        "max_concurrent_agents" => 10,
        "max_retry_backoff_ms" => 300_000,
        "max_turns" => 20
      },
      "runner" => {
        "command" => "codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check -",
        "model" => nil,
        "base_url" => nil,
        "auth_strategy" => "login_then_api_key",
        "api_key" => nil,
        "api_key_env" => "OPENAI_API_KEY",
        "wire_api" => "responses",
        "model_provider" => "symphony_openai_compatible"
      },
      "github" => {
        "repo" => nil,
        "base" => "main",
        "username" => nil,
        "token" => nil,
        "token_env" => nil
      }
    }.freeze

    attr_reader :raw

    def initialize(raw)
      @input_raw = raw.deep_stringify_keys
      @raw = DEFAULTS.deep_merge(@input_raw)
    end

    def tracker_kind
      value_for("tracker", "kind")
    end

    def tracker_account_id
      resolve_env(value_for("tracker", "account_id", optional: true))
    end

    def tracker_board_ids
      board_ids = value_for("tracker", "board_ids", optional: true)
      Array(board_ids).filter_map do |board_id|
        normalized = resolve_env(board_id).to_s.strip
        normalized.presence
      end.presence
    end

    def tracker_active_states
      normalized_states_for(value_for("tracker", "active_states"))
    end

    def tracker_active_column_names
      normalized_names_for(value_for("tracker", "active_column_names", optional: true))
    end

    def tracker_terminal_states
      normalized_states_for(value_for("tracker", "terminal_states"))
    end

    def poll_interval_ms
      value_for("polling", "interval_ms").to_i
    end

    def workspace_root
      Pathname(resolve_env(value_for("workspace", "root"))).expand_path
    end

    def max_concurrent_agents
      value_for("agent", "max_concurrent_agents").to_i
    end

    def max_retry_backoff_ms
      value_for("agent", "max_retry_backoff_ms").to_i
    end

    def max_turns
      value_for("agent", "max_turns").to_i
    end

    def runner_command
      resolve_env(runner_value_for("command", optional: true)).presence || DEFAULTS.dig("runner", "command")
    end

    def runner_base_url
      resolve_env(runner_value_for("base_url", optional: true)).presence
    end

    def runner_auth_strategy
      resolve_env(runner_value_for("auth_strategy", optional: true)).presence || DEFAULTS.dig("runner", "auth_strategy")
    end

    def runner_model
      resolve_env(runner_value_for("model", optional: true)).presence
    end

    def runner_api_key_env
      resolve_env(runner_value_for("api_key_env", optional: true)).presence || DEFAULTS.dig("runner", "api_key_env")
    end

    def runner_api_key
      resolve_env(runner_value_for("api_key", optional: true)).presence
    end

    def runner_wire_api
      resolve_env(runner_value_for("wire_api", optional: true)).presence || DEFAULTS.dig("runner", "wire_api")
    end

    def runner_model_provider
      resolve_env(runner_value_for("model_provider", optional: true)).presence || DEFAULTS.dig("runner", "model_provider")
    end

    def runner_env_vars
      value_for("runner", "env", optional: true) || {}
    end

    def github_repo
      resolve_env(value_for("github", "repo"))
    end

    def github_base
      value_for("github", "base").to_s
    end

    def github_username
      value_for("github", "username").to_s.strip.presence
    end

    def github_token
      resolve_env(value_for("github", "token", optional: true)).presence ||
        resolve_env(value_for("github", "github_token", optional: true)).presence ||
        resolve_env(value_for("github", "token_env", optional: true)).presence
    end

    def validate!
      if tracker_kind != "fizzy"
        raise ConfigurationError, "tracker.kind must be fizzy"
      end

      if tracker_account_id.blank?
        raise ConfigurationError, "tracker.account_id is required for fizzy"
      end

      if tracker_active_states.blank?
        raise ConfigurationError, "tracker.active_states must include at least one state"
      end

      if runner_command.blank?
        raise ConfigurationError, "runner.command is required"
      end

      if runner_command.match?(/\bcodex\s+app-server\b/)
        raise ConfigurationError, "runner.command must run a task executor, not `codex app-server`"
      end

      unless runner_auth_strategy.in?(%w[login_then_api_key login_only api_key_only])
        raise ConfigurationError, "runner.auth_strategy must be one of: login_then_api_key, login_only, api_key_only"
      end

      if github_repo.blank?
        raise ConfigurationError, "github.repo is required"
      end

      if runner_base_url.present? && runner_api_key_env.blank?
        raise ConfigurationError, "runner.api_key_env is required when runner.base_url is set"
      end

      if runner_api_key.present? && runner_api_key_env.blank?
        raise ConfigurationError, "runner.api_key_env is required when runner.api_key is set"
      end

      true
    end

    private
      def value_for(*keys, optional: false)
        keys.reduce(raw) do |cursor, key|
          break nil if optional && !cursor.key?(key)

          cursor.fetch(key)
        end
      end

      def runner_value_for(key, optional: false)
        if @input_raw.dig("runner", key).present?
          value_for("runner", key, optional: optional)
        elsif @input_raw.dig("codex", key).present?
          value_for("codex", key, optional: optional)
        else
          value_for("runner", key, optional: optional)
        end
      end

      def resolve_env(value)
        if value.is_a?(String) && value.start_with?("$")
          ENV[value.delete_prefix("$")]
        else
          value
        end
      end

      def normalized_states_for(values)
        Array(values).filter_map do |state|
          normalized = state.to_s.strip.downcase
          normalized.presence
        end
      end

      def normalized_names_for(values)
        Array(values).filter_map do |value|
          normalized = value.to_s.strip
          normalized.presence
        end.presence
      end
  end
end
