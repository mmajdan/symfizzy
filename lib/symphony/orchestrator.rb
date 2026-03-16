require "set"

module Symphony
  class Orchestrator
    def initialize(config:, workflow_loader:, tracker_client:, workspace_manager:, agent_runner:, pull_request_creator:, logger: Rails.logger, telemetry_logger: nil)
      @config = config
      @workflow_loader = workflow_loader
      @tracker_client = tracker_client
      @workspace_manager = workspace_manager
      @agent_runner = agent_runner
      @pull_request_creator = pull_request_creator
      @logger = logger
      @telemetry_logger = telemetry_logger
      @running = {}
      @claimed = Set.new
      @mutex = Mutex.new
    end

    def tick
      workflow = @workflow_loader.load
      candidates = sort_candidates(@tracker_client.fetch_active_issues)
      available_slots = [ @config.max_concurrent_agents - @running.size, 0 ].max

      @logger.info("Symphony found #{candidates.size} eligible card(s); #{available_slots} slot(s) available")

      candidates.first(available_slots).each do |issue|
        begin
          dispatch_issue_async(issue, workflow)
        rescue => error
          @logger.error("Symphony issue #{issue.identifier} failed to dispatch: #{error.class}: #{error.message}")
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

      def dispatch_issue_async(issue, workflow)
        return if @claimed.include?(issue.id)

        @mutex.synchronize do
          @claimed.add(issue.id)
          @running[issue.id] = issue
        end

        @logger.info("Symphony picking up #{issue.identifier} (state: #{issue.state})")
        emit_telemetry("symphony.issue.pickup", issue: issue, body: "Card picked up by orchestrator")
        log_issue_contents(issue)
        @tracker_client.transition_to_in_progress(issue.id)
        @logger.info("Symphony moved #{issue.identifier} to In Progress (state: #{current_state(issue.id)})")
        emit_telemetry("symphony.issue.transition", issue: issue, body: "Moved to In Progress", attributes: { target_state: "active" })

        # If issue is in rework state, checkout existing branch
        branch_name = issue.state == "rework" ? issue.branch_name : nil
        @logger.info("Symphony creating workspace for #{issue.identifier}...")
        workspace = @workspace_manager.create_for_issue(issue.identifier, branch_name: branch_name)
        @logger.info("Symphony workspace created for #{issue.identifier} at #{workspace.path}")
        emit_telemetry("symphony.workspace.checkout", issue: issue, body: "Repository checked out", attributes: { workspace_path: workspace.path.to_s })
        prompt = PromptRenderer.new.render(
          template: workflow.prompt_template,
          issue: issue,
          attempt: 0,
          turn_number: 1,
          max_turns: @config.max_turns
        )

        @logger.info("Symphony implementing #{issue.identifier} in #{workspace.path}")
        emit_telemetry("symphony.agent.start", issue: issue, body: "Agent run started")

        # Run agent asynchronously in a separate thread
        Thread.new do
          begin
            result = @agent_runner.run(issue: issue, prompt: prompt, workspace_path: workspace.path)

            if result.success
              @logger.info("Symphony implementation finished for #{issue.identifier}; creating PR")
              emit_telemetry("symphony.agent.finish", issue: issue, body: "Agent run finished", attributes: { success: true })
              handle_success(issue, workspace.path, result)
            else
              @logger.error("Symphony implementation failed for #{issue.identifier} (state: #{current_state(issue.id)}): #{result.error || result.stderr}")
              emit_telemetry("symphony.agent.finish", issue: issue, body: "Agent run failed", severity_text: "ERROR", attributes: { success: false, error: result.error || result.stderr })
            end
          rescue => error
            @logger.error("Symphony agent thread failed for #{issue.identifier}: #{error.class}: #{error.message}")
          ensure
            @mutex.synchronize do
              @claimed.delete(issue.id)
              @running.delete(issue.id)
            end
            @logger.info("Symphony agent thread finished for #{issue.identifier}; slot freed")
          end
        end
      end

      def handle_success(issue, workspace_path, result)
        pull_request = @pull_request_creator.create_for(issue: issue, workspace_path: workspace_path)

        if pull_request.success
          @logger.info("Symphony PR created for #{issue.identifier}: #{pull_request.url}")
          emit_telemetry("symphony.pull_request.created", issue: issue, body: "PR created", attributes: { pr_url: pull_request.url })

          begin
            add_summary_comment(issue.id, result.summary)
            @logger.info("Symphony added summary comment for #{issue.identifier}")
          rescue => error
            @logger.error("Symphony failed to add summary comment for #{issue.identifier}: #{error.class}: #{error.message}")
          end

          begin
            @tracker_client.add_comment(issue.id, body: "GitHub PR: #{pull_request.url}")
            @logger.info("Symphony added PR link comment for #{issue.identifier}")
          rescue => error
            @logger.error("Symphony failed to add PR link comment for #{issue.identifier}: #{error.class}: #{error.message}")
          end

          @tracker_client.transition_to_review(issue.id)
          @logger.info("Symphony PR ready for #{issue.identifier}: #{pull_request.url} (state: #{current_state(issue.id)})")
        else
          @logger.error("Symphony implementation finished for #{issue.identifier} but PR creation failed (state: #{current_state(issue.id)}): #{pull_request.error}")
          emit_telemetry("symphony.pull_request.failed", issue: issue, body: "PR creation failed", severity_text: "ERROR", attributes: { error: pull_request.error })
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


      def emit_telemetry(name, issue:, body:, severity_text: "INFO", attributes: {})
        @telemetry_logger&.event(
          name: name,
          issue: issue,
          body: body,
          severity_text: severity_text,
          attributes: attributes
        )
      end

      def add_summary_comment(issue_id, summary)
        return if summary.blank?

        @tracker_client.add_comment(issue_id, body: format_summary_comment(summary))
      end

      def format_summary_comment(summary)
        lines = [ "Implementation summary", "", summary.overview ]

        if summary.files_changed.present?
          lines << ""
          lines << "Files changed:"
          summary.files_changed.each do |file|
            lines << "- #{file}"
          end
        end

        if summary.tests_run.present?
          lines << ""
          lines << "Tests run:"
          summary.tests_run.each do |test|
            lines << "- #{test}"
          end
        end

        if summary.notes.present?
          lines << ""
          lines << "Notes:"
          summary.notes.each do |note|
            lines << "- #{note}"
          end
        end

        lines.join("\n")
      end
  end
end
