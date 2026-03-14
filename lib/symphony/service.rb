module Symphony
  class Service
    def initialize(workflow_path: WorkflowPathResolver.resolve, logger: Rails.logger)
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
          active_column_names: @config.tracker_active_column_names,
          terminal_states: @config.tracker_terminal_states
        )

        Orchestrator.new(
          config: @config,
          workflow_loader: @workflow_loader,
          tracker_client: tracker,
          workspace_manager: WorkspaceManager.new(
            root: @config.workspace_root,
            workflow_path: @workflow_loader.path,
            github_repo: @config.github_repo,
            github_username: @config.github_username,
            github_token: @config.github_token
          ),
          agent_runner: AgentRunner.new(
            command: @config.runner_command,
            model: @config.runner_model,
            base_url: @config.runner_base_url,
            auth_strategy: @config.runner_auth_strategy,
            api_key: @config.runner_api_key,
            api_key_env: @config.runner_api_key_env,
            wire_api: @config.runner_wire_api,
            model_provider: @config.runner_model_provider,
            logger: @logger
          ),
          pull_request_creator: PullRequestCreator.new(repo: @config.github_repo, base_branch: @config.github_base),
          logger: @logger
        )
      end
  end
end
