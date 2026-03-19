require "json"
require "open3"
require "fileutils"
require "shellwords"

module Symphony
  class AgentRunner
    SUMMARY_START_MARKER = "SYMPHONY_SUMMARY_START".freeze
    SUMMARY_END_MARKER = "SYMPHONY_SUMMARY_END".freeze

    Summary = Struct.new(:overview, :files_changed, :tests_run, :notes, keyword_init: true)
    Result = Struct.new(:success, :status, :stdout, :stderr, :error, :auth_mode, :summary, :output_paths, :summary_status, keyword_init: true)
    CHATGPT_LOGIN_MODE = "chatgpt_login".freeze
    API_KEY_MODE = "api_key".freeze
    UNKNOWN_AUTH_MODE = "unknown".freeze
    CODEX_CLI = "codex".freeze
    OPENCODE_CLI = "opencode".freeze

    def initialize(command:, model: nil, base_url: nil, auth_strategy: "login_then_api_key", api_key: nil, api_key_env: "OPENAI_API_KEY", wire_api: "responses", model_provider: "symphony_openai_compatible", env_vars: {}, logger: Rails.logger, telemetry_logger: nil)
      @command = command
      @model = model
      @base_url = base_url
      @auth_strategy = auth_strategy
      @api_key = api_key
      @api_key_env = api_key_env
      @wire_api = wire_api
      @model_provider = model_provider
      @env_vars = env_vars
      @logger = logger
      @telemetry_logger = telemetry_logger
    end

    def run(issue:, prompt:, workspace_path:)
      env = runner_env(issue:, prompt:)

      if prefer_login_auth?
        @logger.info("Symphony agent auth for #{issue.identifier} via #{runner_name}: #{CHATGPT_LOGIN_MODE}")
        result = run_command(issue:, env:, argv: login_command_argv, prompt:, workspace_path:, auth_mode: CHATGPT_LOGIN_MODE)
        return result if result.success || !fallback_to_api_key?(result)

        @logger.info("Symphony agent auth fallback for #{issue.identifier} via #{runner_name}: #{API_KEY_MODE}")
        return run_command(issue:, env: api_key_env(env), argv: api_key_command_argv, prompt:, workspace_path:, auth_mode: API_KEY_MODE)
      end

      if prefer_api_key_auth?
        @logger.info("Symphony agent auth for #{issue.identifier} via #{runner_name}: #{API_KEY_MODE}")
        return run_command(issue:, env: api_key_env(env), argv: api_key_command_argv, prompt:, workspace_path:, auth_mode: API_KEY_MODE)
      end

      @logger.info("Symphony agent auth for #{issue.identifier} via #{runner_name}: default_cli")
      run_command(issue:, env:, argv: login_command_argv, prompt:, workspace_path:, auth_mode: UNKNOWN_AUTH_MODE)
    rescue => error
      @telemetry_logger&.event(name: "symphony.agent.command.exception", issue: issue, body: "Runner raised an exception", severity_text: "ERROR", attributes: { error_class: error.class.name, error_message: error.message })
      Result.new(success: false, status: nil, stdout: "", stderr: "", error: error.message, auth_mode: UNKNOWN_AUTH_MODE, output_paths: {}, summary_status: "unavailable")
    end

    private
      def runner_env(issue:, prompt:)
        base_env = @env_vars.to_h.transform_keys(&:to_s).transform_values(&:to_s)
        base_env.merge({
          "SYMPHONY_ISSUE_ID" => issue.id.to_s,
          "SYMPHONY_ISSUE_IDENTIFIER" => issue.identifier,
          "SYMPHONY_ISSUE_TITLE" => issue.title,
          "SYMPHONY_PROMPT" => prompt
        })
      end

      def run_command(issue:, env:, argv:, prompt:, workspace_path:, auth_mode:)
        command_argv, stdin_data = command_input(argv, prompt)
        stdout, stderr, status = nil

        @telemetry_logger&.event(
          name: "symphony.agent.command.start",
          issue: issue,
          body: "Agent command started",
          attributes: { auth_mode: auth_mode, command: telemetry_command(argv, stdin_data) }
        )

        Timeout.timeout(600) do  # 10 minutes timeout for agent runs
          stdout, stderr, status = Open3.capture3(
            env,
            *command_argv,
            stdin_data: stdin_data,
            chdir: workspace_path.to_s
          )
        end

        output_paths = persist_command_output(workspace_path:, stdout:, stderr:)
        summary, summary_status = extract_summary(stdout)

        result = Result.new(
          success: status.success?,
          status: status.exitstatus,
          stdout: stdout,
          stderr: stderr,
          auth_mode: auth_mode,
          summary: summary,
          output_paths: output_paths,
          summary_status: summary_status
        )

        @telemetry_logger&.event(
          name: "symphony.agent.command.finish",
          issue: issue,
          body: "Agent command finished",
          severity_text: result.success ? "INFO" : "ERROR",
          attributes: {
            auth_mode: auth_mode,
            success: result.success,
            exit_status: result.status,
            stdout_path: output_paths[:stdout_path],
            stderr_path: output_paths[:stderr_path],
            summary_status: summary_status
          }
        )

        emit_summary_telemetry(issue:, result: result)

        result
      end

      def persist_command_output(workspace_path:, stdout:, stderr:)
        output_dir = Pathname(workspace_path).join(".symphony")
        FileUtils.mkdir_p(output_dir)

        stdout_path = output_dir.join("agent.stdout.log")
        stderr_path = output_dir.join("agent.stderr.log")

        stdout_path.write(stdout.to_s)
        stderr_path.write(stderr.to_s)

        { stdout_path: stdout_path.to_s, stderr_path: stderr_path.to_s }
      end

      def emit_summary_telemetry(issue:, result:)
        @telemetry_logger&.event(
          name: "symphony.agent.summary",
          issue: issue,
          body: summary_telemetry_body(result.summary_status),
          severity_text: result.summary_status == "parsed" ? "INFO" : "ERROR",
          attributes: {
            status: result.summary_status,
            stdout_path: result.output_paths[:stdout_path],
            stderr_path: result.output_paths[:stderr_path]
          }
        )
      end

      def summary_telemetry_body(status)
        case status
        when "parsed"
          "Structured summary parsed"
        when "missing_markers"
          "Structured summary markers missing"
        when "invalid_json"
          "Structured summary JSON invalid"
        when "missing_overview"
          "Structured summary missing overview"
        when "invalid_payload"
          "Structured summary payload invalid"
        else
          "Structured summary unavailable"
        end
      end

      def command_input(argv, prompt)
        if runner_name == OPENCODE_CLI
          [ argv + [ prompt ], "" ]
        else
          [ argv, prompt ]
        end
      end

      def telemetry_command(argv, stdin_data)
        command = argv.join(" ")
        stdin_data.present? ? "#{command} [stdin redacted]" : command
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
          output, status = nil
          Timeout.timeout(10) do  # 10 seconds timeout
            output, status = Open3.capture2e(login_status_command)
          end
          status.success? ? output : ""
        rescue Timeout::Error
          ""
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

      def extract_summary(stdout)
        payload = extract_summary_payload(stdout)
        return [ nil, "missing_markers" ] if payload.blank?

        parsed = JSON.parse(payload)
        return [ nil, "invalid_payload" ] unless parsed.is_a?(Hash)

        overview = parsed["summary"].to_s.strip.presence || parsed["overview"].to_s.strip.presence
        return [ nil, "missing_overview" ] if overview.blank?

        [ Summary.new(
            overview: overview,
            files_changed: string_list(parsed["files_changed"]),
            tests_run: string_list(parsed["tests_run"]),
            notes: string_list(parsed["notes"])
          ),
          "parsed" ]
      rescue JSON::ParserError
        [ nil, "invalid_json" ]
      end

      def extract_summary_payload(stdout)
        return if stdout.blank?

        pattern = /#{Regexp.escape(SUMMARY_START_MARKER)}\s*(.*?)\s*#{Regexp.escape(SUMMARY_END_MARKER)}/m
        text_output(stdout)[pattern, 1]
      end

      def text_output(stdout)
        extracted = extract_text_from_event_stream(stdout)
        extracted.presence || stdout
      end

      def extract_text_from_event_stream(stdout)
        texts = stdout.each_line.filter_map do |line|
          next if line.strip.empty?

          parsed = JSON.parse(line)
          next unless parsed["type"] == "text"

          parsed.dig("part", "text")
        rescue JSON::ParserError
          return nil
        end

        texts.join("\n")
      end

      def string_list(value)
        Array(value).filter_map { |item| item.to_s.strip.presence }
      end
  end
end
