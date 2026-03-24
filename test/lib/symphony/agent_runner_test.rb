require "tmpdir"

require "test_helper"

class Symphony::AgentRunnerTest < ActiveSupport::TestCase
  Status = Struct.new(:exitstatus) do
    def success?
      exitstatus.zero?
    end
  end

  class TestLogger
    attr_reader :infos

    def initialize
      @infos = []
    end

    def info(message)
      @infos << message
    end
  end

  class TestTelemetryLogger
    attr_reader :events

    def initialize
      @events = []
    end

    def event(**payload)
      @events << payload
    end
  end

  test "adds codex provider overrides when base url is configured" do
    ENV["CUSTOM_OPENAI_API_KEY"] = "test-key"
    logger = TestLogger.new
    runner = Symphony::AgentRunner.new(
      command: "codex exec --skip-git-repo-check -",
      model: "gpt-4.1-mini",
      base_url: "https://openai-compatible.example/v1",
      api_key_env: "CUSTOM_OPENAI_API_KEY",
      wire_api: "responses",
      model_provider: "custom_provider",
      logger: logger
    )

    issue = Symphony::Issue.new(id: "1", identifier: "CARD-1", title: "Test issue")
    captured = {}

    original_capture3 = Open3.method(:capture3)
    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture3) do |*args, stdin_data:, chdir:|
      captured[:args] = args
      captured[:stdin_data] = stdin_data
      captured[:chdir] = chdir
      [ "stdout", "stderr", Status.new(0) ]
    end
    Open3.define_singleton_method(:capture2e) do |command|
      raise "unexpected command: #{command}"
    end

    begin
      result = runner.run(issue: issue, prompt: "Implement change", workspace_path: Pathname("/tmp/workspace"))

      assert result.success
      assert_equal "api_key", result.auth_mode
    ensure
      Open3.define_singleton_method(:capture3, original_capture3)
      Open3.define_singleton_method(:capture2e, original_capture2e)
      ENV.delete("CUSTOM_OPENAI_API_KEY")
    end

    assert_equal "Implement change", captured[:stdin_data]
    assert_equal "/tmp/workspace", captured[:chdir]

    env = captured[:args].first
    argv = captured[:args].drop(1)

    assert_equal "1", env["SYMPHONY_ISSUE_ID"]
    assert_equal "CARD-1", env["SYMPHONY_ISSUE_IDENTIFIER"]
    assert_equal "Test issue", env["SYMPHONY_ISSUE_TITLE"]
    assert_includes argv, "-m"
    assert_includes argv, "gpt-4.1-mini"
    assert_includes argv, "-c"
    assert_includes argv, "model_providers.custom_provider.base_url=\"https://openai-compatible.example/v1\""
    assert_includes argv, "model_providers.custom_provider.env_key=\"CUSTOM_OPENAI_API_KEY\""
    assert_includes argv, "model_providers.custom_provider.wire_api=\"responses\""
    assert_includes argv, "model_provider=\"custom_provider\""
    assert_equal [ "Symphony agent auth for CARD-1 via codex: api_key" ], logger.infos
  end

  test "prefers chatgpt login auth when available" do
    logger = TestLogger.new
    runner = Symphony::AgentRunner.new(
      command: "codex exec --skip-git-repo-check -",
      model: "gpt-5",
      auth_strategy: "login_then_api_key",
      logger: logger
    )

    issue = Symphony::Issue.new(id: "1", identifier: "CARD-1", title: "Test issue")
    captured = {}

    original_capture3 = Open3.method(:capture3)
    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture2e) do |command|
      if command == "codex login status"
        [ "Logged in using ChatGPT\n", Status.new(0) ]
      else
        raise "unexpected command: #{command}"
      end
    end
    Open3.define_singleton_method(:capture3) do |*args, stdin_data:, chdir:|
      captured[:args] = args
      captured[:stdin_data] = stdin_data
      [ "stdout", "stderr", Status.new(0) ]
    end

    begin
      result = runner.run(issue: issue, prompt: "Implement change", workspace_path: Pathname("/tmp/workspace"))

      assert result.success
      assert_equal "chatgpt_login", result.auth_mode
    ensure
      Open3.define_singleton_method(:capture3, original_capture3)
      Open3.define_singleton_method(:capture2e, original_capture2e)
    end

    argv = captured[:args].drop(1)

    assert_equal [ "Symphony agent auth for CARD-1 via codex: chatgpt_login" ], logger.infos
    assert_includes argv, "-m"
    assert_includes argv, "gpt-5"
  end

  test "extracts structured summary from stdout markers" do
    logger = TestLogger.new
    runner = Symphony::AgentRunner.new(
      command: "codex exec --skip-git-repo-check -",
      model: "gpt-5",
      logger: logger
    )

    issue = Symphony::Issue.new(id: "1", identifier: "CARD-1", title: "Test issue")

    original_capture3 = Open3.method(:capture3)
    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture2e) do |command|
      if command == "codex login status"
        [ "Logged in using ChatGPT\n", Status.new(0) ]
      else
        raise "unexpected command: #{command}"
      end
    end
    Open3.define_singleton_method(:capture3) do |*args, stdin_data:, chdir:|
      stdout = <<~OUT
        work log
        SYMPHONY_SUMMARY_START
        {"summary":"Updated the card workflow and added tests.","files_changed":["lib/symphony/orchestrator.rb","test/lib/symphony/orchestrator_test.rb"],"tests_run":["bin/rails test test/lib/symphony/orchestrator_test.rb"],"notes":["No migration required."]}
        SYMPHONY_SUMMARY_END
      OUT

      [ stdout, "", Status.new(0) ]
    end

    Dir.mktmpdir do |dir|
      workspace_path = Pathname(dir)
      result = runner.run(issue: issue, prompt: "Implement change", workspace_path: workspace_path)

      assert result.success
      assert_equal "Updated the card workflow and added tests.", result.summary.overview
      assert_equal [ "lib/symphony/orchestrator.rb", "test/lib/symphony/orchestrator_test.rb" ], result.summary.files_changed
      assert_equal [ "bin/rails test test/lib/symphony/orchestrator_test.rb" ], result.summary.tests_run
      assert_equal [ "No migration required." ], result.summary.notes
      assert_equal [], result.summary.completed_steps
      assert_equal "parsed", result.summary_status
      assert_equal <<~OUTPUT.strip, result.agent_output
        Stdout

        work log
        SYMPHONY_SUMMARY_START
        {"summary":"Updated the card workflow and added tests.","files_changed":["lib/symphony/orchestrator.rb","test/lib/symphony/orchestrator_test.rb"],"tests_run":["bin/rails test test/lib/symphony/orchestrator_test.rb"],"notes":["No migration required."]}
        SYMPHONY_SUMMARY_END
      OUTPUT
      assert_equal "work log\nSYMPHONY_SUMMARY_START\n{\"summary\":\"Updated the card workflow and added tests.\",\"files_changed\":[\"lib/symphony/orchestrator.rb\",\"test/lib/symphony/orchestrator_test.rb\"],\"tests_run\":[\"bin/rails test test/lib/symphony/orchestrator_test.rb\"],\"notes\":[\"No migration required.\"]}\nSYMPHONY_SUMMARY_END\n", Pathname(result.output_paths[:stdout_path]).read
      assert_equal "", Pathname(result.output_paths[:stderr_path]).read
    end
  ensure
    Open3.define_singleton_method(:capture3, original_capture3)
    Open3.define_singleton_method(:capture2e, original_capture2e)
  end

  test "ignores invalid structured summary payload" do
    logger = TestLogger.new
    runner = Symphony::AgentRunner.new(
      command: "codex exec --skip-git-repo-check -",
      model: "gpt-5",
      logger: logger
    )

    issue = Symphony::Issue.new(id: "1", identifier: "CARD-1", title: "Test issue")

    original_capture3 = Open3.method(:capture3)
    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture2e) do |command|
      if command == "codex login status"
        [ "Logged in using ChatGPT\n", Status.new(0) ]
      else
        raise "unexpected command: #{command}"
      end
    end
    Open3.define_singleton_method(:capture3) do |*args, stdin_data:, chdir:|
      stdout = <<~OUT
        SYMPHONY_SUMMARY_START
        not-json
        SYMPHONY_SUMMARY_END
      OUT

      [ stdout, "", Status.new(0) ]
    end

    Dir.mktmpdir do |dir|
      result = runner.run(issue: issue, prompt: "Implement change", workspace_path: Pathname(dir))

      assert result.success
      assert_nil result.summary
      assert_equal "invalid_json", result.summary_status
    end
  ensure
    Open3.define_singleton_method(:capture3, original_capture3)
    Open3.define_singleton_method(:capture2e, original_capture2e)
  end

  test "emits telemetry when structured summary markers are missing" do
    logger = TestLogger.new
    telemetry = TestTelemetryLogger.new
    runner = Symphony::AgentRunner.new(
      command: "codex exec --skip-git-repo-check -",
      model: "gpt-5",
      telemetry_logger: telemetry,
      logger: logger
    )

    issue = Symphony::Issue.new(id: "1", identifier: "CARD-1", title: "Test issue")

    original_capture3 = Open3.method(:capture3)
    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture2e) do |command|
      if command == "codex login status"
        [ "Logged in using ChatGPT\n", Status.new(0) ]
      else
        raise "unexpected command: #{command}"
      end
    end
    Open3.define_singleton_method(:capture3) do |*args, stdin_data:, chdir:|
      [ "plain stdout without markers", "plain stderr", Status.new(0) ]
    end

    Dir.mktmpdir do |dir|
      result = runner.run(issue: issue, prompt: "Implement change", workspace_path: Pathname(dir))

      assert result.success
      assert_nil result.summary
      assert_equal "missing_markers", result.summary_status

      summary_event = telemetry.events.find { |event| event[:name] == "symphony.agent.summary" }
      assert_equal "ERROR", summary_event[:severity_text]
      assert_equal "missing_markers", summary_event[:attributes][:status]
      assert_equal "plain stdout without markers", Pathname(result.output_paths[:stdout_path]).read
      assert_equal "plain stderr", Pathname(result.output_paths[:stderr_path]).read
    end
  ensure
    Open3.define_singleton_method(:capture3, original_capture3)
    Open3.define_singleton_method(:capture2e, original_capture2e)
  end

  test "falls back to api key when chatgpt login fails for auth reasons" do
    ENV["OPENAI_API_KEY"] = "test-key"
    logger = TestLogger.new
    runner = Symphony::AgentRunner.new(
      command: "codex exec --skip-git-repo-check -",
      model: "gpt-4.1-mini",
      auth_strategy: "login_then_api_key",
      logger: logger
    )

    issue = Symphony::Issue.new(id: "1", identifier: "CARD-1", title: "Test issue")
    calls = []

    original_capture3 = Open3.method(:capture3)
    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture2e) do |command|
      if command == "codex login status"
        [ "Logged in using ChatGPT\n", Status.new(0) ]
      else
        raise "unexpected command: #{command}"
      end
    end
    Open3.define_singleton_method(:capture3) do |env, *argv, stdin_data:, chdir:|
      calls << { env: env, argv: argv }

      if calls.one?
        [ "", "The 'gpt-4.1-mini' model is not supported when using Codex with a ChatGPT account.", Status.new(1) ]
      else
        [ "stdout", "", Status.new(0) ]
      end
    end

    begin
      result = runner.run(issue: issue, prompt: "Implement change", workspace_path: Pathname("/tmp/workspace"))

      assert result.success
      assert_equal "api_key", result.auth_mode
    ensure
      Open3.define_singleton_method(:capture3, original_capture3)
      Open3.define_singleton_method(:capture2e, original_capture2e)
      ENV.delete("OPENAI_API_KEY")
    end

    assert_equal 2, calls.size
    assert_equal "test-key", calls.last[:env]["OPENAI_API_KEY"]
    assert_equal [
      "Symphony agent auth for CARD-1 via codex: chatgpt_login",
      "Symphony agent auth fallback for CARD-1 via codex: api_key"
    ], logger.infos
  end

  test "login_only does not fall back to api key" do
    ENV["OPENAI_API_KEY"] = "test-key"
    logger = TestLogger.new
    runner = Symphony::AgentRunner.new(
      command: "codex exec --skip-git-repo-check -",
      model: "gpt-4.1-mini",
      auth_strategy: "login_only",
      logger: logger
    )

    issue = Symphony::Issue.new(id: "1", identifier: "CARD-1", title: "Test issue")
    calls = []

    original_capture3 = Open3.method(:capture3)
    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture2e) do |command|
      if command == "codex login status"
        [ "Logged in using ChatGPT\n", Status.new(0) ]
      else
        raise "unexpected command: #{command}"
      end
    end
    Open3.define_singleton_method(:capture3) do |env, *argv, stdin_data:, chdir:|
      calls << { env: env, argv: argv }
      [ "", "The 'gpt-4.1-mini' model is not supported when using Codex with a ChatGPT account.", Status.new(1) ]
    end

    begin
      result = runner.run(issue: issue, prompt: "Implement change", workspace_path: Pathname("/tmp/workspace"))

      assert_not result.success
      assert_equal "chatgpt_login", result.auth_mode
    ensure
      Open3.define_singleton_method(:capture3, original_capture3)
      Open3.define_singleton_method(:capture2e, original_capture2e)
      ENV.delete("OPENAI_API_KEY")
    end

    assert_equal 1, calls.size
    assert_equal [ "Symphony agent auth for CARD-1 via codex: chatgpt_login" ], logger.infos
  end

  test "api_key_only skips chatgpt login" do
    ENV["OPENAI_API_KEY"] = "test-key"
    logger = TestLogger.new
    runner = Symphony::AgentRunner.new(
      command: "codex exec --skip-git-repo-check -",
      model: "gpt-4.1-mini",
      auth_strategy: "api_key_only",
      logger: logger
    )

    issue = Symphony::Issue.new(id: "1", identifier: "CARD-1", title: "Test issue")
    captured = {}

    original_capture3 = Open3.method(:capture3)
    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture2e) do |command|
      raise "login status should not be checked: #{command}"
    end
    Open3.define_singleton_method(:capture3) do |env, *argv, stdin_data:, chdir:|
      captured[:env] = env
      captured[:argv] = argv
      captured[:stdin_data] = stdin_data
      [ "stdout", "", Status.new(0) ]
    end

    begin
      result = runner.run(issue: issue, prompt: "Implement change", workspace_path: Pathname("/tmp/workspace"))

      assert result.success
      assert_equal "api_key", result.auth_mode
    ensure
      Open3.define_singleton_method(:capture3, original_capture3)
      Open3.define_singleton_method(:capture2e, original_capture2e)
      ENV.delete("OPENAI_API_KEY")
    end

    assert_equal "test-key", captured[:env]["OPENAI_API_KEY"]
    assert_equal [ "Symphony agent auth for CARD-1 via codex: api_key" ], logger.infos
  end

  test "api_key_only can use literal api key from configuration" do
    logger = TestLogger.new
    runner = Symphony::AgentRunner.new(
      command: "opencode run --format json",
      model: "fireworks-ai/accounts/fireworks/models/kimi-k2p5",
      auth_strategy: "api_key_only",
      api_key: "literal-key",
      api_key_env: "FIREWORKS_API_KEY",
      logger: logger
    )

    issue = Symphony::Issue.new(id: "1", identifier: "CARD-1", title: "Test issue")
    captured = {}

    original_capture3 = Open3.method(:capture3)
    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture2e) do |command|
      raise "login status should not be checked: #{command}"
    end
    Open3.define_singleton_method(:capture3) do |env, *argv, stdin_data:, chdir:|
      captured[:env] = env
      captured[:argv] = argv
      captured[:stdin_data] = stdin_data
      [ "stdout", "", Status.new(0) ]
    end

    begin
      result = runner.run(issue: issue, prompt: "Implement change", workspace_path: Pathname("/tmp/workspace"))

      assert result.success
      assert_equal "api_key", result.auth_mode
    ensure
      Open3.define_singleton_method(:capture3, original_capture3)
      Open3.define_singleton_method(:capture2e, original_capture2e)
    end

    assert_equal "literal-key", captured[:env]["FIREWORKS_API_KEY"]
    assert_equal "", captured[:stdin_data]
    assert_equal "Implement change", captured[:argv].last
    assert_equal [ "Symphony agent auth for CARD-1 via opencode: api_key" ], logger.infos
  end

  test "uses opencode auth list when command runs opencode" do
    logger = TestLogger.new
    runner = Symphony::AgentRunner.new(
      command: "opencode run --format json",
      auth_strategy: "login_only",
      logger: logger
    )

    issue = Symphony::Issue.new(id: "1", identifier: "CARD-1", title: "Test issue")

    original_capture3 = Open3.method(:capture3)
    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture2e) do |command|
      if command == "opencode auth list"
        [ "OpenAI oauth\n", Status.new(0) ]
      else
        raise "unexpected command: #{command}"
      end
    end
    Open3.define_singleton_method(:capture3) do |*args, stdin_data:, chdir:|
      [ "stdout", "", Status.new(0) ]
    end

    begin
      result = runner.run(issue: issue, prompt: "Implement change", workspace_path: Pathname("/tmp/workspace"))

      assert result.success
      assert_equal "chatgpt_login", result.auth_mode
    ensure
      Open3.define_singleton_method(:capture3, original_capture3)
      Open3.define_singleton_method(:capture2e, original_capture2e)
    end

    assert_equal [ "Symphony agent auth for CARD-1 via opencode: chatgpt_login" ], logger.infos
  end

  test "telemetry redacts stdin prompt for codex command logging" do
    logger = TestLogger.new
    telemetry = TestTelemetryLogger.new
    runner = Symphony::AgentRunner.new(
      command: "codex exec --skip-git-repo-check -",
      auth_strategy: "api_key_only",
      api_key: "literal-key",
      telemetry_logger: telemetry,
      logger: logger
    )

    issue = Symphony::Issue.new(id: "1", identifier: "CARD-1", title: "Test issue")

    original_capture3 = Open3.method(:capture3)
    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture2e) do |command|
      raise "login status should not be checked: #{command}"
    end
    Open3.define_singleton_method(:capture3) do |*args, stdin_data:, chdir:|
      [ "stdout", "", Status.new(0) ]
    end

    begin
      result = runner.run(issue: issue, prompt: "Sensitive prompt data", workspace_path: Pathname("/tmp/workspace"))

      assert result.success
    ensure
      Open3.define_singleton_method(:capture3, original_capture3)
      Open3.define_singleton_method(:capture2e, original_capture2e)
    end

    start_event = telemetry.events.find { |event| event[:name] == "symphony.agent.command.start" }
    assert_equal "codex exec --skip-git-repo-check - [stdin redacted]", start_event[:attributes][:command]
  end

  test "telemetry does not include appended opencode prompt in command logging" do
    logger = TestLogger.new
    telemetry = TestTelemetryLogger.new
    runner = Symphony::AgentRunner.new(
      command: "opencode run --format json",
      auth_strategy: "api_key_only",
      api_key: "literal-key",
      telemetry_logger: telemetry,
      logger: logger
    )

    issue = Symphony::Issue.new(id: "1", identifier: "CARD-1", title: "Test issue")

    original_capture3 = Open3.method(:capture3)
    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture2e) do |command|
      raise "login status should not be checked: #{command}"
    end
    Open3.define_singleton_method(:capture3) do |*args, stdin_data:, chdir:|
      [ "stdout", "", Status.new(0) ]
    end

    begin
      result = runner.run(issue: issue, prompt: "Sensitive prompt data", workspace_path: Pathname("/tmp/workspace"))

      assert result.success
    ensure
      Open3.define_singleton_method(:capture3, original_capture3)
      Open3.define_singleton_method(:capture2e, original_capture2e)
    end

    start_event = telemetry.events.find { |event| event[:name] == "symphony.agent.command.start" }
    assert_equal "opencode run --format json", start_event[:attributes][:command]
    assert_no_match(/Sensitive prompt data/, start_event[:attributes][:command])
  end

  test "extracts structured summary from opencode json event stream" do
    logger = TestLogger.new
    runner = Symphony::AgentRunner.new(
      command: "opencode run --format json",
      model: "opencode-go/kimi-k2.5",
      auth_strategy: "api_key_only",
      api_key: "literal-key",
      logger: logger
    )

    issue = Symphony::Issue.new(id: "1", identifier: "CARD-1", title: "Test issue")

    original_capture3 = Open3.method(:capture3)
    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture2e) do |command|
      raise "login status should not be checked: #{command}"
    end
    Open3.define_singleton_method(:capture3) do |*args, stdin_data:, chdir:|
      stdout = <<~OUT
        {"type":"text","part":{"text":"Working..."}}
        {"type":"text","part":{"text":"SYMPHONY_SUMMARY_START\n{\"summary\":\"Updated README and created hello.py\",\"files_changed\":[\"README.md\",\"hello.py\"],\"tests_run\":[\"python3 hello.py\"],\"notes\":[]}\nSYMPHONY_SUMMARY_END"}}
      OUT

      [ stdout, "", Status.new(0) ]
    end

    Dir.mktmpdir do |dir|
      result = runner.run(issue: issue, prompt: "Implement change", workspace_path: Pathname(dir))

      assert result.success
      assert_equal "parsed", result.summary_status
      assert_equal "Updated README and created hello.py", result.summary.overview
      assert_equal [ "README.md", "hello.py" ], result.summary.files_changed
      assert_equal [ "python3 hello.py" ], result.summary.tests_run
    end
  ensure
    Open3.define_singleton_method(:capture3, original_capture3)
    Open3.define_singleton_method(:capture2e, original_capture2e)
  end

  test "extracts readable agent output from json event stream and stderr" do
    runner = Symphony::AgentRunner.new(
      command: "opencode run --format json",
      model: "gpt-5",
      logger: TestLogger.new
    )

    issue = Symphony::Issue.new(id: "1", identifier: "CARD-1", title: "Test issue")

    original_capture3 = Open3.method(:capture3)
    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture2e) do |command|
      if command == "opencode auth list"
        [ "OpenAI oauth", Status.new(0) ]
      else
        raise "unexpected command: #{command}"
      end
    end
    Open3.define_singleton_method(:capture3) do |*args, stdin_data:, chdir:|
      stdout = <<~OUT
        {"type":"text","part":{"text":"Started work"}}
        {"type":"text","part":{"text":"Implemented feature"}}
      OUT

      [ stdout, "warning output", Status.new(0) ]
    end

    Dir.mktmpdir do |dir|
      result = runner.run(issue: issue, prompt: "Implement change", workspace_path: Pathname(dir))

      assert result.success
      assert_equal <<~OUTPUT.strip, result.agent_output
        Stdout

        Started work
        Implemented feature

        Stderr

        warning output
      OUTPUT
    end
  ensure
    Open3.define_singleton_method(:capture3, original_capture3)
    Open3.define_singleton_method(:capture2e, original_capture2e)
  end

  test "extracts completed steps from structured summary" do
    runner = Symphony::AgentRunner.new(
      command: "codex exec --skip-git-repo-check -",
      model: "gpt-5",
      logger: TestLogger.new
    )

    issue = Symphony::Issue.new(id: "1", identifier: "CARD-1", title: "Test issue")

    original_capture3 = Open3.method(:capture3)
    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture2e) do |command|
      if command == "codex login status"
        [ "Logged in using ChatGPT\n", Status.new(0) ]
      else
        raise "unexpected command: #{command}"
      end
    end
    Open3.define_singleton_method(:capture3) do |*args, stdin_data:, chdir:|
      stdout = <<~OUT
        SYMPHONY_SUMMARY_START
        {"summary":"Completed card steps","completed_steps":["Follow the first step","[todo] Another step"]}
        SYMPHONY_SUMMARY_END
      OUT

      [ stdout, "", Status.new(0) ]
    end

    Dir.mktmpdir do |dir|
      result = runner.run(issue: issue, prompt: "Implement change", workspace_path: Pathname(dir))

      assert result.success
      assert_equal [ "Follow the first step", "[todo] Another step" ], result.summary.completed_steps
    end
  ensure
    Open3.define_singleton_method(:capture3, original_capture3)
    Open3.define_singleton_method(:capture2e, original_capture2e)
  end
end
