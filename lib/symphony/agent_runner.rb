require "json"
require "open3"
require "shellwords"

module Symphony
  class AgentRunner
    Result = Struct.new(:success, :status, :stdout, :stderr, :error, :auth_mode, keyword_init: true)
    CHATGPT_LOGIN_MODE = "chatgpt_login".freeze
    API_KEY_MODE = "api_key".freeze
    UNKNOWN_AUTH_MODE = "unknown".freeze
    CODEX_CLI = "codex".freeze
    OPENCODE_CLI = "opencode".freeze

    def initialize(command:, model: nil, base_url: nil, auth_strategy: "login_then_api_key", api_key: nil, api_key_env: "OPENAI_API_KEY", wire_api: "responses", model_provider: "symphony_openai_compatible", logger: Rails.logger)
      @command = command
      @model = model
      @base_url = base_url
      @auth_strategy = auth_strategy
      @api_key = api_key
      @api_key_env = api_key_env
      @wire_api = wire_api
      @model_provider = model_provider
      @logger = logger
    end

    def run(issue:, prompt:, workspace_path:)
      env = runner_env(issue:, prompt:)

      if prefer_login_auth?
        @logger.info("Symphony agent auth for #{issue.identifier} via #{runner_name}: #{CHATGPT_LOGIN_MODE}")
        result = run_command(env:, argv: login_command_argv, prompt:, workspace_path:, auth_mode: CHATGPT_LOGIN_MODE)
        return result if result.success || !fallback_to_api_key?(result)

        @logger.info("Symphony agent auth fallback for #{issue.identifier} via #{runner_name}: #{API_KEY_MODE}")
        return run_command(env: api_key_env(env), argv: api_key_command_argv, prompt:, workspace_path:, auth_mode: API_KEY_MODE)
      end

      if prefer_api_key_auth?
        @logger.info("Symphony agent auth for #{issue.identifier} via #{runner_name}: #{API_KEY_MODE}")
        return run_command(env: api_key_env(env), argv: api_key_command_argv, prompt:, workspace_path:, auth_mode: API_KEY_MODE)
      end

      @logger.info("Symphony agent auth for #{issue.identifier} via #{runner_name}: default_cli")
      run_command(env:, argv: login_command_argv, prompt:, workspace_path:, auth_mode: UNKNOWN_AUTH_MODE)
    rescue => error
      Result.new(success: false, status: nil, stdout: "", stderr: "", error: error.message, auth_mode: UNKNOWN_AUTH_MODE)
    end

    private
      def runner_env(issue:, prompt:)
        {
          "SYMPHONY_ISSUE_ID" => issue.id,
          "SYMPHONY_ISSUE_IDENTIFIER" => issue.identifier,
          "SYMPHONY_ISSUE_TITLE" => issue.title,
          "SYMPHONY_PROMPT" => prompt
        }
      end

      def run_command(env:, argv:, prompt:, workspace_path:, auth_mode:)
        command_argv, stdin_data = command_input(argv, prompt)
        stdout, stderr, status = Open3.capture3(
          env,
          *command_argv,
          stdin_data: stdin_data,
          chdir: workspace_path.to_s
        )

        Result.new(success: status.success?, status: status.exitstatus, stdout: stdout, stderr: stderr, auth_mode: auth_mode)
      end

      def command_input(argv, prompt)
        if runner_name == OPENCODE_CLI
          [ argv + [ prompt ], "" ]
        else
          [ argv, prompt ]
        end
      end

      def login_command_argv
        argv = Shellwords.split(@command)
        argv += [ "-m", @model ] if @model.present?

        argv
      end

      def api_key_command_argv
        argv = login_command_argv

        return argv if @base_url.blank?

        argv + [
          "-c", "model_providers.#{@model_provider}.name=\"Symphony OpenAI Compatible\"",
          "-c", "model_providers.#{@model_provider}.base_url=#{@base_url.to_json}",
          "-c", "model_providers.#{@model_provider}.env_key=#{@api_key_env.to_json}",
          "-c", "model_providers.#{@model_provider}.wire_api=#{@wire_api.to_json}",
          "-c", "model_provider=#{@model_provider.to_json}"
        ]
      end

      def login_auth_supported?
        return false if @base_url.present?

        case runner_name
        when CODEX_CLI
          login_status.include?("Logged in using ChatGPT")
        when OPENCODE_CLI
          login_status.match?(/\bOpenAI\b.*\boauth\b/i) || login_status.match?(/\bcodex\b.*\boauth\b/i)
        else
          false
        end
      end

      def prefer_login_auth?
        return false unless @auth_strategy.in?([ "login_then_api_key", "login_only" ])
        return false unless login_auth_supported?

        true
      end

      def prefer_api_key_auth?
        return true if @base_url.present? && api_key_auth_supported?
        return false unless api_key_auth_supported?

        @auth_strategy == "api_key_only"
      end

      def api_key_auth_supported?
        @api_key.present? || ENV[@api_key_env].present?
      end

      def fallback_to_api_key?(result)
        @auth_strategy == "login_then_api_key" && api_key_auth_supported? && auth_failure?(result)
      end

      def auth_failure?(result)
        output = [ result.stdout, result.stderr, result.error ].compact.join("\n")

        output.match?(/ChatGPT account/i) ||
          output.match?(/codex login/i) ||
          output.match?(/opencode auth/i) ||
          output.match?(/unauthorized/i) ||
          output.match?(/authentication/i) ||
          output.match?(/\b401\b/)
      end

      def api_key_env(env)
        env.merge(@api_key_env => resolved_api_key)
      end

      def resolved_api_key
        @api_key.presence || ENV[@api_key_env]
      end

      def login_status
        @login_status ||= begin
          output, status = Open3.capture2e(login_status_command)
          status.success? ? output : ""
        end
      end

      def login_status_command
        case runner_name
        when CODEX_CLI
          "codex login status"
        when OPENCODE_CLI
          "opencode auth list"
        else
          ""
        end
      end

      def runner_name
        @runner_name ||= Shellwords.split(@command).first.to_s
      end
  end
end
