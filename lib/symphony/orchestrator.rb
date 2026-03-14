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

      @logger.info("Symphony found #{candidates.size} eligible card(s); #{available_slots} slot(s) available")

      candidates.first(available_slots).each do |issue|
        begin
          dispatch_issue(issue, workflow)
        rescue => error
          @logger.error("Symphony issue #{issue.identifier} failed: #{error.class}: #{error.message}")
        end
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
        @logger.info("Symphony picking up #{issue.identifier} (state: #{issue.state})")
        log_issue_contents(issue)
        @tracker_client.transition_to_in_progress(issue.id)
        @logger.info("Symphony moved #{issue.identifier} to In Progress (state: #{current_state(issue.id)})")

        workspace = @workspace_manager.create_for_issue(issue.identifier)
        prompt = PromptRenderer.new.render(
          template: workflow.prompt_template,
          issue: issue,
          attempt: 0,
          turn_number: 1,
          max_turns: @config.max_turns
        )

        @logger.info("Symphony implementing #{issue.identifier} in #{workspace.path}")
        result = @agent_runner.run(issue: issue, prompt: prompt, workspace_path: workspace.path)

        if result.success
          @logger.info("Symphony implementation finished for #{issue.identifier}; creating PR")
          handle_success(issue, workspace.path)
        else
          @logger.error("Symphony implementation failed for #{issue.identifier} (state: #{current_state(issue.id)}): #{result.error || result.stderr}")
        end
      ensure
        @claimed.delete(issue.id)
      end

      def handle_success(issue, workspace_path)
        pull_request = @pull_request_creator.create_for(issue: issue, workspace_path: workspace_path)

        if pull_request.success
          @tracker_client.add_comment(issue.id, body: "GitHub PR: #{pull_request.url}")
          @tracker_client.transition_to_review(issue.id)
          @logger.info("Symphony PR ready for #{issue.identifier}: #{pull_request.url} (state: #{current_state(issue.id)})")
        else
          @logger.error("Symphony implementation finished for #{issue.identifier} but PR creation failed (state: #{current_state(issue.id)}): #{pull_request.error}")
        end
      end

      def current_state(issue_id)
        @tracker_client.fetch_issue(issue_id)&.state || "unknown"
      end

      def log_issue_contents(issue)
        details = [
          "title=#{issue.title.inspect}",
          ("description=#{issue.description.inspect}" if issue.description.present?),
          ("priority=#{issue.priority}" if issue.priority),
          ("state=#{issue.state}" if issue.state),
          ("url=#{issue.url}" if issue.url),
          ("labels=#{issue.labels.join(",")}" if issue.labels.present?)
        ].compact

        @logger.info("Symphony card contents for #{issue.identifier}: #{details.join(" ")}")
      end
  end
end
