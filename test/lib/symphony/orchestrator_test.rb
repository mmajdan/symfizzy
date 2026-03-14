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
    attr_reader :handled_identifiers

    def initialize
      @handled_identifiers = []
    end

    def create_for_issue(identifier)
      @handled_identifiers << identifier
      OpenStruct.new(path: "/tmp/#{identifier}")
    end
  end

  class FakeWorkflowLoader
    def load
      OpenStruct.new(prompt_template: "Process {{ issue.identifier }}")
    end
  end

  class FakePullRequestCreator
    attr_reader :handled_ids

    def initialize(result: OpenStruct.new(success: true, url: nil))
      @result = result
      @handled_ids = []
    end

    def create_for(issue:, workspace_path:)
      @handled_ids << issue.id
      @result
    end
  end

  class FakeTrackerClient
    attr_reader :comments, :in_progress_ids, :transitioned_ids

    def initialize(issues)
      @issues = issues
      @comments = []
      @in_progress_ids = []
      @transitioned_ids = []
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

    def transition_to_review(id)
      @transitioned_ids << id
      update_issue_state(id, "review")
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

    assert_equal [ "2" ], recording_runner.handled_ids
    assert_equal [ "1", "2" ], tracker.in_progress_ids
    assert_empty tracker.comments
    assert_empty tracker.transitioned_ids
    assert_equal [ "CARD-1", "CARD-2" ], workspace_manager.handled_identifiers
    assert logger.infos.any? { |message| message.include?("picking up CARD-1") }
    assert logger.infos.any? { |message| message.include?("implementing CARD-2") }
    assert logger.errors.any? { |message| message.include?("CARD-1") }
  end

  test "does not transition issue to review when no changes were produced" do
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

    assert_equal [ "1" ], tracker.in_progress_ids
    assert_empty tracker.comments
    assert_empty tracker.transitioned_ids
    assert logger.infos.any? { |message| message.include?("implementation finished for CARD-1; creating PR") }
    assert logger.errors.any? { |message| message.include?("No changes produced in workspace") }
  end

  test "adds card comment with PR URL before transitioning issue to review" do
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
      pull_request_creator: FakePullRequestCreator.new(result: OpenStruct.new(success: true, url: "https://github.com/org/repo/pull/1")),
      logger: logger
    )

    orchestrator.tick

    assert_equal [ "1" ], tracker.in_progress_ids
    assert_equal [ { id: "1", body: "GitHub PR: https://github.com/org/repo/pull/1" } ], tracker.comments
    assert_equal [ "1" ], tracker.transitioned_ids
    assert logger.infos.any? { |message| message.include?("PR ready for CARD-1: https://github.com/org/repo/pull/1 (state: review)") }
  end

  class MultiRunner
    def initialize(runners)
      @runners = runners
    end

    def run(issue:, prompt:, workspace_path:)
      @runners.fetch(issue.identifier).run(issue: issue, prompt: prompt, workspace_path: workspace_path)
    end
  end
end
