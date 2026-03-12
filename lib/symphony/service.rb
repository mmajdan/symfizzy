module Symphony
  class Service
    def initialize(workflow_path: Rails.root.join("WORKFLOW.md"), logger: Rails.logger)
      @workflow_loader = WorkflowLoader.new(path: workflow_path)
      @config = Config.new(@workflow_loader.load.config)
      @config.validate!
      @logger = logger
    end

    def run(once: false)
      orchestrator = build_orchestrator

      if once
        orchestrator.tick
      else
        loop do
          orchestrator.tick
          sleep(@config.poll_interval_ms / 1000.0)
        end
      end
    end

    private
      def build_orchestrator
        tracker = IssueTrackers::FizzyClient.new(
          account_id: @config.tracker_account_id,
          board_ids: @config.tracker_board_ids,
          active_states: @config.tracker_active_states,
          terminal_states: @config.tracker_terminal_states
        )

        Orchestrator.new(
          config: @config,
          workflow_loader: @workflow_loader,
          tracker_client: tracker,
          workspace_manager: WorkspaceManager.new(root: @config.workspace_root),
          agent_runner: AgentRunner.new(command: @config.codex_command),
          logger: @logger
        )
      end
  end
end
