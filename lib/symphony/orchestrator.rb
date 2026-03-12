require "set"

module Symphony
  class Orchestrator
    def initialize(config:, workflow_loader:, tracker_client:, workspace_manager:, agent_runner:, pull_request_creator:, logger: Rails.logger)
      @config = config
      @workflow_loader = workflow_loader
      @tracker_client = tracker_client
      @workspace_manager = workspace_manager
      @agent_runner = agent_runner
      @pull_request_creator = pull_request_creator
      @logger = logger
      @running = {}
      @claimed = Set.new
    end

    def tick
      workflow = @workflow_loader.load
      candidates = sort_candidates(@tracker_client.fetch_active_issues)
      available_slots = [ @config.max_concurrent_agents - @running.size, 0 ].max

      candidates.first(available_slots).each do |issue|
        dispatch_issue(issue, workflow)
      end
    rescue => error
      @logger.error("Symphony tick failed: #{error.class}: #{error.message}")
      raise
    end

    private
      def sort_candidates(candidates)
        candidates.sort_by do |issue|
          [ issue.priority || 999, issue.created_at || Time.current, issue.identifier ]
        end
      end

      def dispatch_issue(issue, workflow)
        return if @claimed.include?(issue.id)

        @claimed.add(issue.id)

        workspace = @workspace_manager.create_for_issue(issue.identifier)
        prompt = PromptRenderer.new.render(
          template: workflow.prompt_template,
          issue: issue,
          attempt: 0,
          turn_number: 1,
          max_turns: @config.max_turns
        )

        result = @agent_runner.run(issue: issue, prompt: prompt, workspace_path: workspace.path)

        if result.success
          handle_success(issue, workspace.path)
        else
          @logger.error("Symphony failed #{issue.identifier}: #{result.error || result.stderr}")
        end
      ensure
        @claimed.delete(issue.id)
      end

      def handle_success(issue, workspace_path)
        pull_request = @pull_request_creator.create_for(issue: issue, workspace_path: workspace_path)

        if pull_request.success
          @tracker_client.transition_to_review(issue.id)
          @logger.info("Symphony finished #{issue.identifier}#{" with PR #{pull_request.url}" if pull_request.url.present?}")
        else
          @logger.error("Symphony finished #{issue.identifier} but failed to create PR: #{pull_request.error}")
        end
      end
  end
end
