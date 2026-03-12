module Symphony
  module IssueTrackers
    class FizzyClient
      def initialize(account_id:, board_ids: nil, active_states:, terminal_states:)
        @account = Account.find_by!(external_account_id: account_id)
        @board_ids = board_ids
        @active_states = active_states
        @terminal_states = terminal_states
      end

      def fetch_active_issues
        cards = scoped_cards.includes(:board, :closure, :not_now, :tags).select(&:published?)
        cards.filter_map do |card|
          issue = to_issue(card)
          issue if @active_states.include?(issue.state)
        end
      end

      def fetch_issue(issue_id)
        card = scoped_cards.find_by(id: issue_id)

        if card
          to_issue(card)
        end
      end

      def fetch_terminal_issues
        cards = scoped_cards.includes(:board, :closure, :not_now, :tags).select(&:published?)
        cards.filter_map do |card|
          issue = to_issue(card)
          issue if @terminal_states.include?(issue.state)
        end
      end

      private
        def scoped_cards
          relation = @account.cards
          relation = relation.where(board_id: @board_ids) if @board_ids.present?
          relation
        end

        def to_issue(card)
          Issue.new(
            id: card.id,
            identifier: "CARD-#{card.number}",
            title: card.title,
            description: card.description&.to_plain_text,
            priority: nil,
            state: state_for(card),
            branch_name: "card-#{card.number}",
            url: Rails.application.routes.url_helpers.card_path(card, script_name: "/#{@account.external_account_id}"),
            labels: card.tags.map { |tag| tag.name.downcase },
            blocked_by: [],
            created_at: card.created_at,
            updated_at: card.updated_at
          )
        end

        def state_for(card)
          if card.closed?
            "closed"
          elsif card.postponed?
            "not_now"
          else
            "active"
          end
        end
    end
  end
end
