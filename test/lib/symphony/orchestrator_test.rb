require "test_helper"

class Symphony::OrchestratorTest < ActiveSupport::TestCase
  class TestLogger
    attr_reader :errors

    def initialize
      @errors = []
    end

    def error(message)
      @errors << message
    end

    def info(_message)
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
    def create_for_issue(identifier)
      OpenStruct.new(path: "/tmp/#{identifier}")
    end
  end

  class FakeWorkflowLoader
    def load
      OpenStruct.new(prompt_template: "Process {{ issue.identifier }}")
    end
  end

  class FakePullRequestCreator
    def create_for(issue:, workspace_path:)
      OpenStruct.new(success: true, url: nil)
    end
  end

  class FakeTrackerClient
    def initialize(issues)
      @issues = issues
    end

    def fetch_active_issues
      @issues
    end

    def transition_to_review(_id)
    end
  end

  test "continues processing after one issue fails" do
    first_issue = Symphony::Issue.new(id: "1", identifier: "CARD-1")
    second_issue = Symphony::Issue.new(id: "2", identifier: "CARD-2")
    logger = TestLogger.new
    recording_runner = RecordingAgentRunner.new

    orchestrator = Symphony::Orchestrator.new(
      config: OpenStruct.new(max_concurrent_agents: 10, max_turns: 20),
      workflow_loader: FakeWorkflowLoader.new,
      tracker_client: FakeTrackerClient.new([ first_issue, second_issue ]),
      workspace_manager: FakeWorkspaceManager.new,
      agent_runner: MultiRunner.new(
        "CARD-1" => FailingAgentRunner.new,
        "CARD-2" => recording_runner
      ),
      pull_request_creator: FakePullRequestCreator.new,
      logger: logger
    )

    orchestrator.tick

    assert_equal [ "2" ], recording_runner.handled_ids
    assert logger.errors.any? { |message| message.include?("CARD-1") }
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
