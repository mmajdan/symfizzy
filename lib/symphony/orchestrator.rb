require "set"
require "symphony/turn_state"

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
      @idle_condition = ConditionVariable.new
      @turn_state_registry = TurnStateRegistry.new
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
          @logger.error("Symphony issue #{issue.identifier} failed to dispatch: #{error.class}: #{error.message}")
        end
      end
    rescue => error
      @logger.error("Symphony tick failed: #{error.class}: #{error.message}")
      raise
    end

    def wait_until_idle(timeout: nil)
      deadline = timeout ? Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout : nil

      @mutex.synchronize do
        until @running.empty?
          break if deadline_reached?(deadline)

          remaining = deadline && deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @idle_condition.wait(@mutex, remaining || 0.1)
        end
      end
    end

    private
      def deadline_reached?(deadline)
        deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      end

      def sort_candidates(candidates)
        candidates.sort_by do |issue|
          [ issue.priority || 999, issue.created_at || Time.current, issue.identifier ]
        end
      end

      def dispatch_issue(issue, workflow)
        if @turn_state_registry.active?(issue.id)
          # Continue existing multi-turn sequence
          continue_turn_async(issue, workflow)
        else
          # Start fresh sequence
          start_turn_sequence_async(issue, workflow)
        end
      end

      def start_turn_sequence_async(issue, workflow)
        return if @claimed.include?(issue.id)

        @mutex.synchronize do
          @claimed.add(issue.id)
          @running[issue.id] = issue
        end

        original_state = issue.state
        @logger.info("Symphony picking up #{issue.identifier} (state: #{issue.state})")
        emit_telemetry("symphony.issue.pickup", issue: issue, body: "Card picked up by orchestrator")
        log_issue_contents(issue)

        if original_state == "merging"
          dispatch_merge_async(issue)
          return
        end

        @tracker_client.transition_to_in_progress(issue.id)
        @logger.info("Symphony moved #{issue.identifier} to In Progress (state: #{current_state(issue.id)})")
        emit_telemetry("symphony.issue.transition", issue: issue, body: "Moved to In Progress", attributes: { target_state: "active" })

        # If issue is in rework state, checkout existing branch
        branch_name = original_state == "rework" ? issue.branch_name : nil
        @logger.info("Symphony creating workspace for #{issue.identifier}...")
        workspace = @workspace_manager.create_for_issue(issue.identifier, branch_name: branch_name)
        @logger.info("Symphony workspace created for #{issue.identifier} at #{workspace.path}")

        # Register turn state for this issue
        @turn_state_registry.register(issue.id, workspace.path)

        emit_telemetry("symphony.workspace.checkout", issue: issue, body: "Repository checked out", attributes: { workspace_path: workspace.path.to_s })

        # Start first turn
        run_turn_async(issue, workflow, original_state)
      end

      def continue_turn_async(issue, workflow)
        return if @claimed.include?(issue.id)

        @mutex.synchronize do
          @claimed.add(issue.id)
          @running[issue.id] = issue
        end

        @logger.info("Symphony continuing multi-turn sequence for #{issue.identifier}")

        # Run next turn
        run_turn_async(issue, workflow, issue.state)
      end

      def run_turn_async(issue, workflow, original_state)
        turn_state = @turn_state_registry.get(issue.id)
        turn_number = turn_state&.current_turn || 1

        Thread.new do
          begin
            prompt = PromptRenderer.new.render(
              template: workflow.prompt_template,
              issue: issue,
              attempt: 0,
              turn_number: turn_number,
              max_turns: @config.max_turns,
              previous_turn_output: turn_state&.previous_outputs&.last
            )

            @logger.info("Symphony implementing #{issue.identifier} turn #{turn_number}/#{@config.max_turns}")
            emit_telemetry("symphony.agent.prompt", issue: issue, body: "Agent prompt rendered for turn #{turn_number}", attributes: { prompt: prompt, turn_number: turn_number })
            emit_telemetry("symphony.agent.turn.start", issue: issue, body: "Agent turn #{turn_number} started", attributes: { turn_number: turn_number, max_turns: @config.max_turns })

            workspace_path = turn_state&.workspace_path || "/tmp/#{issue.identifier}"
            result = @agent_runner.run(issue: issue, prompt: prompt, workspace_path: workspace_path)

            if result.success
              handle_turn_result(issue, workflow, result, original_state, turn_state)
            else
              @logger.error("Symphony implementation failed for #{issue.identifier} turn #{turn_number}: #{result.error || result.stderr}")
              emit_telemetry("symphony.agent.turn.finish", issue: issue, body: "Agent turn #{turn_number} failed", severity_text: "ERROR", attributes: { turn_number: turn_number, success: false, error: result.error || result.stderr })
              transition_to_retry(issue, previous_state: original_state)
              cleanup_turn_state(issue.id)
            end
          rescue => error
            @logger.error("Symphony agent thread failed for #{issue.identifier}: #{error.class}: #{error.message}")
            transition_to_retry(issue, previous_state: original_state)
            cleanup_turn_state(issue.id)
          ensure
            @mutex.synchronize do
              @claimed.delete(issue.id)
              @running.delete(issue.id)
              @idle_condition.broadcast if @running.empty?
            end
            @logger.info("Symphony agent thread finished for #{issue.identifier} turn #{turn_number}; slot freed")
          end
        end
      end

      def handle_turn_result(issue, workflow, result, original_state, turn_state)
        current_turn = turn_state&.current_turn || 1
        should_continue = result.summary&.continue == true

        emit_telemetry("symphony.agent.turn.finish", issue: issue, body: "Agent turn #{current_turn} finished", attributes: { turn_number: current_turn, success: true, continue: should_continue })

        if should_continue && current_turn < @config.max_turns
          # Continue to next turn
          @logger.info("Symphony continuing to turn #{current_turn + 1} for #{issue.identifier}")

          # Auto-commit changes from this turn
          workspace_path = turn_state.workspace_path
          commit_message = "Turn #{current_turn} completed - #{issue.identifier}"
          if @workspace_manager.commit_changes(workspace_path, commit_message)
            @logger.info("Symphony auto-committed changes for #{issue.identifier} turn #{current_turn}")
          end

          # Increment turn and continue
          @turn_state_registry.increment_turn(issue.id, result.stdout)

          # Release slot and schedule next turn
          @mutex.synchronize do
            @claimed.delete(issue.id)
            @running.delete(issue.id)
            @idle_condition.broadcast if @running.empty?
          end

          # Immediately dispatch next turn
          dispatch_issue(issue, workflow)
        elsif should_continue && current_turn >= @config.max_turns
          # Max turns exceeded
          @logger.warn("Symphony max turns (#{@config.max_turns}) exceeded for #{issue.identifier}")
          emit_telemetry("symphony.agent.multi_turn.complete", issue: issue, body: "Multi-turn sequence incomplete - max turns exceeded", severity_text: "WARN", attributes: { turns_completed: current_turn, max_turns: @config.max_turns })

          # Add incomplete comment and move to review
          begin
            @tracker_client.add_comment(issue.id, body: "Implementation incomplete: reached maximum of #{@config.max_turns} turns without completion. Please review the work done so far.")
            @logger.info("Symphony added incomplete comment for #{issue.identifier}")
          rescue => error
            @logger.error("Symphony failed to add incomplete comment for #{issue.identifier}: #{error.class}: #{error.message}")
          end

          @tracker_client.transition_to_review(issue.id)
          @logger.info("Symphony moved #{issue.identifier} to Review after max turns exceeded (state: #{current_state(issue.id)})")
          cleanup_turn_state(issue.id)
        else
          # Agent finished (continue: false or not specified)
          @logger.info("Symphony implementation finished for #{issue.identifier}; creating PR")
          emit_telemetry("symphony.agent.finish", issue: issue, body: "Agent run finished", attributes: { success: true, turns_completed: current_turn })
          handle_success(issue, turn_state.workspace_path, result, previous_state: original_state)
          cleanup_turn_state(issue.id)
        end
      end

      def cleanup_turn_state(issue_id)
        @turn_state_registry.remove(issue_id)
      end

      def dispatch_merge_async(issue)
        Thread.new do
          begin
            @logger.info("Symphony merging PR for #{issue.identifier}")
            emit_telemetry("symphony.pull_request.merge.start", issue: issue, body: "PR merge started", attributes: { pr_url: issue.pr_url })
            result = merge_pull_request(issue)

            if result.success
              @tracker_client.add_comment(issue.id, body: "GitHub PR merged successfully: #{result.url}")
              @tracker_client.transition_to_done(issue.id)
              @logger.info("Symphony merged PR for #{issue.identifier}: #{result.url} (state: #{current_state(issue.id)})")
              emit_telemetry("symphony.pull_request.merge.finish", issue: issue, body: "PR merge finished", attributes: { success: true, pr_url: result.url })
            else
              handle_merge_failure(issue, result.error)
            end
          rescue => error
            handle_merge_failure(issue, "#{error.class}: #{error.message}")
          ensure
            @mutex.synchronize do
              @claimed.delete(issue.id)
              @running.delete(issue.id)
              @idle_condition.broadcast if @running.empty?
            end
            @logger.info("Symphony merge thread finished for #{issue.identifier}; slot freed")
          end
        end
      end

      def handle_success(issue, workspace_path, result, previous_state:)
        sync_completed_steps(issue.id, result.summary)
        pull_request = @pull_request_creator.create_for(issue: issue, workspace_path: workspace_path)

        if pull_request.success
          @logger.info("Symphony PR created for #{issue.identifier}: #{pull_request.url}")
          emit_telemetry("symphony.pull_request.created", issue: issue, body: "PR created", attributes: { pr_url: pull_request.url })

          summary_comment_body = result.summary.present? ? format_summary_comment(result.summary) : nil

          begin
            if add_summary_comment(issue.id, result.summary, body: summary_comment_body)
              @logger.info("Symphony added summary comment for #{issue.identifier}")
            else
              @logger.info("Symphony skipped summary comment for #{issue.identifier}: no parsed summary available")
            end
          rescue => error
            @logger.error("Symphony failed to add summary comment for #{issue.identifier}: #{error.class}: #{error.message}")
          end

          begin
            if add_pull_request_summary_comment(pull_request.url, workspace_path, summary_comment_body)
              @logger.info("Symphony added PR summary comment for #{issue.identifier}")
            else
              @logger.info("Symphony skipped PR summary comment for #{issue.identifier}: no parsed summary available")
            end
          rescue => error
            @logger.error("Symphony failed to add PR summary comment for #{issue.identifier}: #{error.class}: #{error.message}")
          end

          begin
            @tracker_client.add_comment(issue.id, body: "GitHub PR: #{pull_request.url}")
            @logger.info("Symphony added PR link comment for #{issue.identifier}")
          rescue => error
            @logger.error("Symphony failed to add PR link comment for #{issue.identifier}: #{error.class}: #{error.message}")
          end

          @tracker_client.transition_to_review(issue.id)
          @logger.info("Symphony PR ready for #{issue.identifier}: #{pull_request.url} (state: #{current_state(issue.id)})")
        elsif no_changes_produced?(pull_request)
          @logger.info("Symphony implementation produced no workspace changes for #{issue.identifier}; moving to Review")

          begin
            @tracker_client.add_comment(issue.id, body: pull_request.error)
            @logger.info("Symphony added no-op comment for #{issue.identifier}")
          rescue => error
            @logger.error("Symphony failed to add no-op comment for #{issue.identifier}: #{error.class}: #{error.message}")
          end

          @tracker_client.transition_to_review(issue.id)
          @logger.info("Symphony moved #{issue.identifier} to Review without PR update (state: #{current_state(issue.id)})")
        else
          @logger.error("Symphony implementation finished for #{issue.identifier} but PR creation failed (state: #{current_state(issue.id)}): #{pull_request.error}")
          emit_telemetry("symphony.pull_request.failed", issue: issue, body: "PR creation failed", severity_text: "ERROR", attributes: { error: pull_request.error })
          transition_to_retry(issue, previous_state: previous_state)
        end
      end

      def merge_pull_request(issue)
        if issue.pr_url.blank?
          return Symphony::PullRequestCreator::Result.new(success: false, error: "No GitHub PR URL found in card comments")
        end

        @pull_request_creator.merge(pr_url: issue.pr_url, workspace_path: Rails.root)
      end

      def handle_merge_failure(issue, error_message)
        @logger.error("Symphony failed to merge PR for #{issue.identifier}: #{error_message}")
        emit_telemetry("symphony.pull_request.merge.finish", issue: issue, body: "PR merge failed", severity_text: "ERROR", attributes: { success: false, error: error_message, pr_url: issue.pr_url })

        begin
          @tracker_client.add_comment(issue.id, body: "GitHub PR merge failed: #{error_message}")
        rescue => error
          @logger.error("Symphony failed to add merge failure comment for #{issue.identifier}: #{error.class}: #{error.message}")
        end

        begin
          @tracker_client.transition_to_review(issue.id)
          @logger.info("Symphony moved #{issue.identifier} to Review after merge failure (state: #{current_state(issue.id)})")
        rescue => error
          @logger.error("Symphony failed to move #{issue.identifier} to Review after merge failure: #{error.class}: #{error.message}")
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

      def add_summary_comment(issue_id, summary, body: nil)
        return false if summary.blank?

        @tracker_client.add_comment(issue_id, body: body || format_summary_comment(summary))
        true
      end

      def add_pull_request_summary_comment(pr_url, workspace_path, body)
        return false if body.blank?

        @pull_request_creator.add_comment(pr_url: pr_url, body: body, workspace_path: workspace_path)
        true
      end

      def sync_completed_steps(issue_id, summary)
        completed_steps = summary&.completed_steps
        return false if completed_steps.blank?

        updated_count = @tracker_client.complete_steps(issue_id, completed_steps: completed_steps)
        @logger.info("Symphony marked #{updated_count} card step(s) complete for #{issue_id}")
        updated_count.positive?
      rescue => error
        @logger.error("Symphony failed to complete card steps for #{issue_id}: #{error.class}: #{error.message}")
        false
      end

      def no_changes_produced?(pull_request)
        pull_request.error == "No changes produced in workspace"
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

      def transition_to_retry(issue, previous_state:)
        @tracker_client.transition_to_retry(issue.id, previous_state: previous_state)
        @logger.info("Symphony moved #{issue.identifier} back to retryable column (state: #{current_state(issue.id)})")
      rescue => error
        @logger.error("Symphony failed to move #{issue.identifier} back to retryable column: #{error.class}: #{error.message}")
      end
  end
end
