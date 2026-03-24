require "ostruct"

require "test_helper"

class Symphony::OrchestratorTest < ActiveSupport::TestCase
  class TestLogger
    attr_reader :errors, :infos

    def initialize
      @errors = []
      @infos = []
    end

    def error(message)
      @errors << message
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

  class FailingAgentRunner
    def run(issue:, prompt:, workspace_path:)
      raise "boom for #{issue.identifier}"
    end
  end

  class RecordingAgentRunner
    attr_reader :handled_ids

    def initialize
      @handled_ids = []
    end

    def run(issue:, prompt:, workspace_path:)
      @handled_ids << issue.id
      OpenStruct.new(success: false, error: nil, stderr: "no-op")
    end
  end

  class FakeWorkspaceManager
    attr_reader :handled_identifiers, :handled_branch_names

    def initialize
      @handled_identifiers = []
      @handled_branch_names = []
    end

    def create_for_issue(identifier, branch_name: nil)
      @handled_identifiers << identifier
      @handled_branch_names << branch_name
      OpenStruct.new(path: "/tmp/#{identifier}")
    end
  end

  class FakeWorkflowLoader
    def load
      OpenStruct.new(prompt_template: "Process {{ issue.identifier }}")
    end
  end

  class FakePullRequestCreator
    attr_reader :handled_ids, :comment_calls

    def initialize(result: OpenStruct.new(success: true, url: nil))
      @result = result
      @handled_ids = []
      @comment_calls = []
    end

    def create_for(issue:, workspace_path:)
      @handled_ids << issue.id
      @result
    end

    def add_comment(pr_url:, body:, workspace_path:)
      @comment_calls << { pr_url: pr_url, body: body, workspace_path: workspace_path }
      true
    end
  end

  class FakeTrackerClient
    attr_reader :comments, :in_progress_ids, :transitioned_ids, :retry_ids, :completed_steps_calls

    def initialize(issues)
      @issues = issues
      @comments = []
      @in_progress_ids = []
      @transitioned_ids = []
      @retry_ids = []
      @completed_steps_calls = []
    end

    def fetch_active_issues
      @issues
    end

    def fetch_issue(id)
      @issues.find { |issue| issue.id == id }
    end

    def transition_to_in_progress(id)
      @in_progress_ids << id
      update_issue_state(id, "active")
    end

    def add_comment(id, body:)
      @comments << { id: id, body: body }
    end

    def complete_steps(id, completed_steps:)
      @completed_steps_calls << { id: id, completed_steps: completed_steps }
      completed_steps.size
    end

    def transition_to_review(id)
      @transitioned_ids << id
      update_issue_state(id, "review")
    end

    def transition_to_retry(id, previous_state:)
      @retry_ids << { id: id, previous_state: previous_state }
      update_issue_state(id, previous_state)
    end

    private
      def update_issue_state(id, state)
        issue = @issues.find { |candidate| candidate.id == id }
        issue.state = state if issue
      end
  end

  test "continues processing after one issue fails" do
    first_issue = Symphony::Issue.new(id: "1", identifier: "CARD-1")
    second_issue = Symphony::Issue.new(id: "2", identifier: "CARD-2")
    logger = TestLogger.new
    recording_runner = RecordingAgentRunner.new
    tracker = FakeTrackerClient.new([ first_issue, second_issue ])
    workspace_manager = FakeWorkspaceManager.new

    orchestrator = Symphony::Orchestrator.new(
      config: OpenStruct.new(max_concurrent_agents: 10, max_turns: 20),
      workflow_loader: FakeWorkflowLoader.new,
      tracker_client: tracker,
      workspace_manager: workspace_manager,
      agent_runner: MultiRunner.new(
        "CARD-1" => FailingAgentRunner.new,
        "CARD-2" => recording_runner
      ),
      pull_request_creator: FakePullRequestCreator.new,
      logger: logger
    )

    orchestrator.tick

    wait_until { recording_runner.handled_ids == [ "2" ] }

    assert_equal [ "2" ], recording_runner.handled_ids
    assert_equal [ "1", "2" ], tracker.in_progress_ids
    assert_equal 2, tracker.retry_ids.size
    assert_includes tracker.retry_ids,({ id: "1", previous_state: nil })
    assert_includes tracker.retry_ids,({ id: "2", previous_state: nil })
    assert_empty tracker.comments
    assert_empty tracker.transitioned_ids
    assert_equal [ "CARD-1", "CARD-2" ], workspace_manager.handled_identifiers
    assert logger.infos.any? { |message| message.include?("picking up CARD-1") }
    assert logger.infos.any? { |message| message.include?("implementing CARD-2") }
    assert logger.errors.any? { |message| message.include?("CARD-1") }
  end

  test "transitions issue to review with a card comment when no changes were produced" do
    issue = Symphony::Issue.new(id: "1", identifier: "CARD-1", state: "active")
    logger = TestLogger.new
    tracker = FakeTrackerClient.new([ issue ])
    runner = Class.new do
      def run(issue:, prompt:, workspace_path:)
        OpenStruct.new(success: true, error: nil, stderr: "")
      end
    end.new

    orchestrator = Symphony::Orchestrator.new(
      config: OpenStruct.new(max_concurrent_agents: 10, max_turns: 20),
      workflow_loader: FakeWorkflowLoader.new,
      tracker_client: tracker,
      workspace_manager: FakeWorkspaceManager.new,
      agent_runner: runner,
      pull_request_creator: FakePullRequestCreator.new(result: OpenStruct.new(success: false, error: "No changes produced in workspace")),
      logger: logger
    )

    orchestrator.tick

    wait_until { tracker.comments.present? && tracker.transitioned_ids.present? }

    assert_equal [ "1" ], tracker.in_progress_ids
    assert_empty tracker.retry_ids
    assert_equal [ { id: "1", body: "No changes produced in workspace" } ], tracker.comments
    assert_equal [ "1" ], tracker.transitioned_ids
    assert logger.infos.any? { |message| message.include?("implementation finished for CARD-1; creating PR") }
    assert logger.infos.any? { |message| message.include?("moving to Review") }
  end

  test "adds card comment with PR URL before transitioning issue to review" do
    issue = Symphony::Issue.new(id: "1", identifier: "CARD-1", state: "active")
    logger = TestLogger.new
    tracker = FakeTrackerClient.new([ issue ])
    runner = Class.new do
      def run(issue:, prompt:, workspace_path:)
        OpenStruct.new(success: true, error: nil, stderr: "", summary: nil)
      end
    end.new

    orchestrator = Symphony::Orchestrator.new(
      config: OpenStruct.new(max_concurrent_agents: 10, max_turns: 20),
      workflow_loader: FakeWorkflowLoader.new,
      tracker_client: tracker,
      workspace_manager: FakeWorkspaceManager.new,
      agent_runner: runner,
      pull_request_creator: FakePullRequestCreator.new(result: OpenStruct.new(success: true, url: "https://github.com/org/repo/pull/1")),
      logger: logger
    )

    orchestrator.tick

    wait_until { tracker.comments.present? && tracker.transitioned_ids.present? }

    assert_equal [ "1" ], tracker.in_progress_ids
    assert_equal [ { id: "1", body: "GitHub PR: https://github.com/org/repo/pull/1" } ], tracker.comments
    assert_equal [ "1" ], tracker.transitioned_ids
    assert logger.infos.any? { |message| message.include?("skipped summary comment for CARD-1") }
    assert logger.infos.any? { |message| message.include?("PR ready for CARD-1: https://github.com/org/repo/pull/1 (state: review)") }
  end

  test "moves failed active issues back to retryable state" do
    issue = Symphony::Issue.new(id: "1", identifier: "CARD-1", state: "active")
    tracker = FakeTrackerClient.new([ issue ])
    runner = Class.new do
      def run(issue:, prompt:, workspace_path:)
        OpenStruct.new(success: false, error: "execution expired", stderr: nil)
      end
    end.new

    orchestrator = Symphony::Orchestrator.new(
      config: OpenStruct.new(max_concurrent_agents: 10, max_turns: 20),
      workflow_loader: FakeWorkflowLoader.new,
      tracker_client: tracker,
      workspace_manager: FakeWorkspaceManager.new,
      agent_runner: runner,
      pull_request_creator: FakePullRequestCreator.new,
      logger: TestLogger.new
    )

    orchestrator.tick

    wait_until { tracker.retry_ids == [ { id: "1", previous_state: "active" } ] }

    assert_equal [ "1" ], tracker.in_progress_ids
    assert_equal [ { id: "1", previous_state: "active" } ], tracker.retry_ids
    assert_equal "active", tracker.fetch_issue("1").state
  end

  test "moves failed rework issues back to retryable state" do
    issue = Symphony::Issue.new(id: "1", identifier: "CARD-1", state: "rework", branch_name: "card-1")
    tracker = FakeTrackerClient.new([ issue ])
    runner = Class.new do
      def run(issue:, prompt:, workspace_path:)
        OpenStruct.new(success: false, error: "execution expired", stderr: nil)
      end
    end.new
    workspace_manager = FakeWorkspaceManager.new

    orchestrator = Symphony::Orchestrator.new(
      config: OpenStruct.new(max_concurrent_agents: 10, max_turns: 20),
      workflow_loader: FakeWorkflowLoader.new,
      tracker_client: tracker,
      workspace_manager: workspace_manager,
      agent_runner: runner,
      pull_request_creator: FakePullRequestCreator.new,
      logger: TestLogger.new
    )

    orchestrator.tick

    wait_until { tracker.retry_ids == [ { id: "1", previous_state: "rework" } ] }

    assert_equal [ "1" ], tracker.in_progress_ids
    assert_equal [ { id: "1", previous_state: "rework" } ], tracker.retry_ids
    assert_equal [ "card-1" ], workspace_manager.handled_branch_names
    assert_equal "rework", tracker.fetch_issue("1").state
  end

  test "adds structured implementation summary comment before PR comment" do
    issue = Symphony::Issue.new(id: "1", identifier: "CARD-1", state: "active")
    logger = TestLogger.new
    tracker = FakeTrackerClient.new([ issue ])
    summary = Symphony::AgentRunner::Summary.new(
      overview: "Updated Symphony to post implementation summaries to cards.",
      files_changed: [ "lib/symphony/agent_runner.rb", "lib/symphony/orchestrator.rb" ],
      tests_run: [ "bin/rails test test/lib/symphony/orchestrator_test.rb" ],
      notes: [ "Falls back to PR-only comments if the summary block is missing." ],
      completed_steps: [ "Follow the first step", "Run the second step" ]
    )
    runner = Class.new do
      define_method(:initialize) { |summary| @summary = summary }

      define_method(:run) do |issue:, prompt:, workspace_path:|
        OpenStruct.new(success: true, error: nil, stderr: "", summary: @summary)
      end
    end.new(summary)

    pull_request_creator = FakePullRequestCreator.new(result: OpenStruct.new(success: true, url: "https://github.com/org/repo/pull/1"))

    orchestrator = Symphony::Orchestrator.new(
      config: OpenStruct.new(max_concurrent_agents: 10, max_turns: 20),
      workflow_loader: FakeWorkflowLoader.new,
      tracker_client: tracker,
      workspace_manager: FakeWorkspaceManager.new,
      agent_runner: runner,
      pull_request_creator: pull_request_creator,
      logger: logger
    )

    orchestrator.tick

    wait_until { tracker.comments.size == 2 && tracker.transitioned_ids == [ "1" ] }

    assert_equal [ "1" ], tracker.in_progress_ids
    assert_equal 2, tracker.comments.size
    assert_equal "1", tracker.comments.first[:id]
    assert_equal <<~BODY.strip, tracker.comments.first[:body]
      Implementation summary

      Updated Symphony to post implementation summaries to cards.

      Files changed:
      - lib/symphony/agent_runner.rb
      - lib/symphony/orchestrator.rb

      Tests run:
      - bin/rails test test/lib/symphony/orchestrator_test.rb

      Notes:
      - Falls back to PR-only comments if the summary block is missing.
    BODY
    assert_equal({ id: "1", body: "GitHub PR: https://github.com/org/repo/pull/1" }, tracker.comments.second)
    assert_equal [ {
      pr_url: "https://github.com/org/repo/pull/1",
      body: tracker.comments.first[:body],
      workspace_path: "/tmp/CARD-1"
    } ], pull_request_creator.comment_calls
    assert_equal [ {
      id: "1",
      completed_steps: [ "Follow the first step", "Run the second step" ]
    } ], tracker.completed_steps_calls
    assert_equal [ "1" ], tracker.transitioned_ids
  end

  test "emits rendered agent prompt to telemetry for rework issues" do
    issue = Symphony::Issue.new(
      id: "1",
      identifier: "CARD-1",
      title: "Prompt test",
      state: "rework",
      pr_url: "https://github.com/org/repo/pull/1",
      comments: [ "Please update the README", "Adjust the script output" ]
    )
    telemetry = TestTelemetryLogger.new
    tracker = FakeTrackerClient.new([ issue ])
    runner = Class.new do
      def run(issue:, prompt:, workspace_path:)
        OpenStruct.new(success: false, error: nil, stderr: "stop after prompt")
      end
    end.new
    workflow_loader = Class.new do
      def load
        OpenStruct.new(prompt_template: "State {{ issue.state }} PR {{ issue.pr_url }} Comments {{ issue.comments }}")
      end
    end.new

    orchestrator = Symphony::Orchestrator.new(
      config: OpenStruct.new(max_concurrent_agents: 10, max_turns: 20),
      workflow_loader: workflow_loader,
      tracker_client: tracker,
      workspace_manager: FakeWorkspaceManager.new,
      agent_runner: runner,
      pull_request_creator: FakePullRequestCreator.new,
      telemetry_logger: telemetry
    )

    orchestrator.tick

    wait_until { telemetry.events.any? { |event| event[:name] == "symphony.agent.prompt" } }

    prompt_event = telemetry.events.find { |event| event[:name] == "symphony.agent.prompt" }
    assert prompt_event.present?
    assert_equal issue.id, prompt_event[:issue].id
    assert_includes prompt_event.dig(:attributes, :prompt), issue.pr_url
    assert_includes prompt_event.dig(:attributes, :prompt), "Please update the README"
  end

  class MultiRunner
    def initialize(runners)
      @runners = runners
    end

    def run(issue:, prompt:, workspace_path:)
      @runners.fetch(issue.identifier).run(issue: issue, prompt: prompt, workspace_path: workspace_path)
    end
  end

  private
    def wait_until(timeout: 1)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

      loop do
        return if yield
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep 0.01
      end

      flunk "Condition not met within #{timeout} seconds"
    end
end
