module Symphony
  module IssueTrackers
    class FizzyClient
      REVIEW_STATE = "review".freeze
      MERGING_STATE = "merging".freeze
      ACTIVE_STATE = "active".freeze
      CLOSED_STATE = "closed".freeze
      NOT_NOW_STATE = "not_now".freeze
      DONE_STATE = "done".freeze
      TODO_COLUMN_NAME = "todo".freeze
      IN_PROGRESS_COLUMN_NAME = "In Progress".freeze

      def initialize(account_id:, board_ids: nil, active_states:, active_column_names: nil, terminal_states:)
        @account = Account.find_by!(external_account_id: account_id)
        @board_ids = board_ids
        @active_states = active_states.map(&:downcase)
        @active_column_names = Array(active_column_names).filter_map { |name| name.to_s.strip.downcase.presence }.presence
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

      def add_comment(issue_id, body:)
        card = scoped_cards.find(issue_id)

        Current.set(account: @account, user: @account.system_user) do
          card.comments.create!(body: body)
        end
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
            updated_at: card.updated_at
          )
        end

        def state_for(card)
          if card.closed?
            CLOSED_STATE
          elsif card.postponed?
            NOT_NOW_STATE
          elsif active_column?(card)
            ACTIVE_STATE
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
          return false unless issue_state == ACTIVE_STATE

          @active_column_names.include?(card.column&.name.to_s.strip.downcase)
        end
    end
  end
end
