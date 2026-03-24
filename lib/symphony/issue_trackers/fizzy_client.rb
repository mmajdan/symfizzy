module Symphony
  module IssueTrackers
    class FizzyClient
      REVIEW_STATE = "review".freeze
      MERGING_STATE = "merging".freeze
      ACTIVE_STATE = "active".freeze
      REWORK_STATE = "rework".freeze
      CLOSED_STATE = "closed".freeze
      NOT_NOW_STATE = "not_now".freeze
      DONE_STATE = "done".freeze
      TODO_COLUMN_NAME = "todo".freeze
      TODO_COLUMN_LABEL = "Todo".freeze
      IN_PROGRESS_COLUMN_NAME = "In Progress".freeze
      REWORK_COLUMN_NAME = "rework".freeze
      REWORK_COLUMN_LABEL = "Rework".freeze

      def initialize(account_id:, board_ids: nil, active_states:, active_column_names: nil, terminal_states:)
        @account = Account.find_by!(external_account_id: account_id)
        @board_ids = board_ids
        @active_states = active_states.map(&:downcase)
        @active_column_labels = Array(active_column_names).filter_map { |name| name.to_s.strip.presence }.presence
        @active_column_names = @active_column_labels&.map(&:downcase)
        @terminal_states = terminal_states.map(&:downcase)
      end

      def fetch_active_issues
        cards = scoped_cards.includes(:board, :closure, :not_now, :tags, :column).select(&:published?)

        cards.filter_map do |card|
          issue = to_issue(card)
          issue if @active_states.include?(issue.state) && active_column_allowed?(card, issue.state)
        end
      end

      def fetch_issue(issue_id)
        card = scoped_cards.find_by(id: issue_id)

        if card
          to_issue(card)
        end
      end

      def fetch_terminal_issues
        cards = scoped_cards.includes(:board, :closure, :not_now, :tags, :column).select(&:published?)

        cards.filter_map do |card|
          issue = to_issue(card)
          issue if @terminal_states.include?(issue.state)
        end
      end

      def transition_to_review(issue_id)
        card = scoped_cards.find(issue_id)
        review_column = card.board.columns.find_or_create_by!(name: "Review") do |column|
          column.color = "var(--color-card-3)"
          column.position = card.board.columns.maximum(:position).to_i + 1
          column.account = @account
        end

        Current.set(account: @account, user: @account.system_user) do
          card.triage_into(review_column)
        end
      end

      def transition_to_in_progress(issue_id)
        card = scoped_cards.find(issue_id)
        in_progress_column = card.board.columns.find_or_create_by!(name: IN_PROGRESS_COLUMN_NAME) do |column|
          column.color = "var(--color-card-2)"
          column.position = card.board.columns.maximum(:position).to_i + 1
          column.account = @account
        end

        return if card.column == in_progress_column

        Current.set(account: @account, user: @account.system_user) do
          card.triage_into(in_progress_column)
        end
      end

      def transition_to_retry(issue_id, previous_state:)
        card = scoped_cards.find(issue_id)
        retry_column = retry_column_for(card.board, previous_state: previous_state)

        return if card.column == retry_column

        Current.set(account: @account, user: @account.system_user) do
          card.triage_into(retry_column)
        end
      end

      def add_comment(issue_id, body:)
        card = scoped_cards.find(issue_id)

        Current.set(account: @account, user: @account.system_user) do
          card.comments.create!(body: body)
        end
      end

      def complete_steps(issue_id, completed_steps:)
        targets = normalized_completed_steps(completed_steps)
        return 0 if targets.empty?

        card = scoped_cards.includes(:steps).find(issue_id)
        steps_to_complete = card.steps.reject(&:completed?).select do |step|
          targets.include?(normalize_step_content(step.content))
        end

        Current.set(account: @account, user: @account.system_user) do
          steps_to_complete.each { |step| step.update!(completed: true) }
        end

        steps_to_complete.size
      end

      private
        def scoped_cards
          relation = @account.cards
          relation = relation.where(board_id: @board_ids) if @board_ids.present?
          relation
        end

        def to_issue(card)
          Symphony::Issue.new(
            id: card.id,
            identifier: "CARD-#{card.number}",
            title: card.title,
            description: card.description&.to_plain_text,
            priority: nil,
            state: state_for(card),
            branch_name: "card-#{card.number}",
            url: Rails.application.routes.url_helpers.card_path(card, script_name: "/#{@account.external_account_id}"),
            labels: card.tags.map { |tag| tag.title.downcase },
            blocked_by: [],
            created_at: card.created_at,
            updated_at: card.updated_at,
            pr_url: extract_pr_url(card),
            comments: extract_comments(card),
            steps: extract_steps(card)
          )
        end

        def extract_pr_url(card)
          # Look for GitHub PR URL in card comments
          card.comments.each do |comment|
            body = comment.body.to_plain_text
            if match = body.match(%r{https://github\.com/[^/]+/[^/]+/pull/\d+})
              return match[0]
            end
          end
          nil
        end

        def extract_comments(card)
          # Extract all card comments as array of strings
          card.comments.map { |c| c.body.to_plain_text }.reject(&:blank?)
        end

        def extract_steps(card)
          card.steps.order(:id).filter_map do |step|
            content = step.content.to_s.strip
            next if content.blank?

            prefix = step.completed? ? "[done]" : "[todo]"
            "#{prefix} #{content}"
          end
        end

        def normalized_completed_steps(completed_steps)
          Array(completed_steps).filter_map do |step|
            normalize_step_content(step)
          end
        end

        def normalize_step_content(content)
          normalized = content.to_s.strip.sub(/\A\[(?:todo|done)\]\s*/i, "").strip
          normalized.presence
        end

        def state_for(card)
          if card.closed?
            CLOSED_STATE
          elsif card.postponed?
            NOT_NOW_STATE
          elsif active_column?(card)
            ACTIVE_STATE
          elsif rework_column?(card)
            REWORK_STATE
          elsif done_column?(card)
            DONE_STATE
          elsif review_column?(card)
            REVIEW_STATE
          elsif merging_column?(card)
            MERGING_STATE
          else
            NOT_NOW_STATE
          end
        end

        def active_column?(card)
          [ TODO_COLUMN_NAME, IN_PROGRESS_COLUMN_NAME ].any? do |column_name|
            card.column&.name.to_s.casecmp(column_name).zero?
          end
        end

        def rework_column?(card)
          card.column&.name.to_s.casecmp(REWORK_COLUMN_NAME).zero?
        end

        def review_column?(card)
          card.column&.name.to_s.casecmp(REVIEW_STATE).zero?
        end

        def merging_column?(card)
          card.column&.name.to_s.casecmp(MERGING_STATE).zero?
        end

        def done_column?(card)
          card.column&.name.to_s.casecmp(DONE_STATE).zero?
        end

        def active_column_allowed?(card, issue_state)
          return true if @active_column_names.blank?
          return false unless @active_states.include?(issue_state)

          @active_column_names.include?(card.column&.name.to_s.strip.downcase)
        end

        def retry_column_for(board, previous_state:)
          if previous_state.to_s.casecmp(REWORK_STATE).zero?
            find_or_create_column(board, name: retry_rework_column_name, color: "var(--color-card-1)")
          else
            find_or_create_column(board, name: retry_active_column_name, color: "var(--color-card-1)")
          end
        end

        def retry_active_column_name
          configured_retry_column = Array(@active_column_labels).find do |name|
            !name.casecmp(REWORK_COLUMN_NAME).zero? && !name.casecmp(IN_PROGRESS_COLUMN_NAME).zero?
          end

          configured_retry_column || TODO_COLUMN_LABEL
        end

        def retry_rework_column_name
          configured_rework_column = Array(@active_column_labels).find do |name|
            name.casecmp(REWORK_COLUMN_NAME).zero?
          end

          configured_rework_column || REWORK_COLUMN_LABEL
        end

        def find_or_create_column(board, name:, color:)
          board.columns.detect { |column| column.name.to_s.casecmp(name).zero? } ||
            board.columns.create!(
              name: name,
              color: color,
              position: board.columns.maximum(:position).to_i + 1,
              account: @account
            )
        end
    end
  end
end
