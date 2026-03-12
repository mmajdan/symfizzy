require "tmpdir"

module Symphony
  class Config
    DEFAULTS = {
      "tracker" => {
        "kind" => "fizzy",
        "active_states" => [ "active", "review", "merging" ],
        "terminal_states" => [ "closed", "not_now" ]
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
      "codex" => {
        "command" => "codex app-server"
      },
      "github" => {
        "repo" => nil,
        "base" => "main"
      }
    }.freeze

    attr_reader :raw

    def initialize(raw)
      @raw = DEFAULTS.deep_merge(raw.deep_stringify_keys)
    end

    def tracker_kind
      value_for("tracker", "kind")
    end

    def tracker_account_id
      resolve_env(value_for("tracker", "account_id"))
    end

    def tracker_board_ids
      Array(value_for("tracker", "board_ids")).presence
    end

    def tracker_active_states
      Array(value_for("tracker", "active_states")).map { |state| state.to_s.downcase }
    end

    def tracker_terminal_states
      Array(value_for("tracker", "terminal_states")).map { |state| state.to_s.downcase }
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

    def codex_command
      value_for("codex", "command").to_s
    end

    def github_repo
      resolve_env(value_for("github", "repo"))
    end

    def github_base
      value_for("github", "base").to_s
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

      if codex_command.blank?
        raise ConfigurationError, "codex.command is required"
      end

      true
    end

    private
      def value_for(*keys)
        keys.reduce(raw) { |cursor, key| cursor.fetch(key) }
      end

      def resolve_env(value)
        if value.is_a?(String) && value.start_with?("$")
          ENV[value.delete_prefix("$")]
        else
          value
        end
      end
  end
end
