require "test_helper"

class Symphony::FizzyClientTest < ActiveSupport::TestCase
  test "returns active cards normalized as issues" do
    client = Symphony::IssueTrackers::FizzyClient.new(
      account_id: accounts(:"37s").external_account_id,
      active_states: [ "active", "review", "merging" ],
      terminal_states: [ "closed", "not_now" ]
    )

    issues = client.fetch_active_issues

    assert issues.any?
    assert issues.all? { |issue| issue.identifier.start_with?("CARD-") }
  end

  test "maps review and merging based on column name" do
    review_card = cards(:buy_domain)
    review_card.update!(column: columns(:writebook_review))

    merging_column = boards(:writebook).columns.create!(
      name: "Merging",
      color: "var(--color-card-2)",
      position: 99,
      account: accounts(:"37s")
    )
    merging_card = cards(:logo)
    merging_card.update!(column: merging_column)

    client = Symphony::IssueTrackers::FizzyClient.new(
      account_id: accounts(:"37s").external_account_id,
      active_states: [ "active", "review", "merging" ],
      terminal_states: [ "closed", "not_now" ]
    )

    assert_equal "review", client.fetch_issue(review_card.id).state
    assert_equal "merging", client.fetch_issue(merging_card.id).state
  end

  test "maps done based on column name and treats it as terminal" do
    done_column = boards(:writebook).columns.create!(
      name: "Done",
      color: "var(--color-card-3)",
      position: 100,
      account: accounts(:"37s")
    )
    done_card = cards(:layout)
    done_card.update!(column: done_column)

    client = Symphony::IssueTrackers::FizzyClient.new(
      account_id: accounts(:"37s").external_account_id,
      active_states: [ "active" ],
      terminal_states: [ "closed", "not_now", "done" ]
    )

    assert_equal "done", client.fetch_issue(done_card.id).state
    assert_includes client.fetch_terminal_issues.map(&:id), done_card.id
    assert_not_includes client.fetch_active_issues.map(&:id), done_card.id
  end

  test "transitions completed issue to review" do
    client = Symphony::IssueTrackers::FizzyClient.new(
      account_id: accounts(:"37s").external_account_id,
      active_states: [ "active", "review", "merging" ],
      terminal_states: [ "closed", "not_now" ]
    )

    card = cards(:buy_domain)
    card.update!(column: nil)

    client.transition_to_review(card.id)

    assert_equal "Review", card.reload.column.name
  end

  test "transitions picked issue to in progress" do
    client = Symphony::IssueTrackers::FizzyClient.new(
      account_id: accounts(:"37s").external_account_id,
      active_states: [ "active", "review", "merging" ],
      terminal_states: [ "closed", "not_now", "done" ]
    )

    card = cards(:buy_domain)
    card.update!(column: nil)

    client.transition_to_in_progress(card.id)

    assert_equal "In Progress", card.reload.column.name
  end

  test "does not re-triage card already in progress" do
    client = Symphony::IssueTrackers::FizzyClient.new(
      account_id: accounts(:"37s").external_account_id,
      active_states: [ "active", "review", "merging" ],
      terminal_states: [ "closed", "not_now", "done" ]
    )

    card = cards(:buy_domain)
    in_progress_column = card.board.columns.create!(
      name: "In Progress",
      color: "var(--color-card-2)",
      position: 98,
      account: accounts(:"37s")
    )
    card.update!(column: in_progress_column)

    assert_no_changes -> { card.events.count } do
      client.transition_to_in_progress(card.id)
    end
  end

  test "adds a system comment to the card" do
    client = Symphony::IssueTrackers::FizzyClient.new(
      account_id: accounts(:"37s").external_account_id,
      active_states: [ "active" ],
      terminal_states: [ "closed", "not_now" ]
    )

    card = cards(:buy_domain)

    assert_difference -> { card.comments.count }, +1 do
      client.add_comment(card.id, body: "GitHub PR: https://github.com/example/repo/pull/123")
    end

    comment = card.comments.order(:created_at).last

    assert_equal accounts(:"37s").system_user, comment.creator
    assert_equal "GitHub PR: https://github.com/example/repo/pull/123", comment.body.to_plain_text.strip
  end

  test "supports filtering by board ids" do
    client = Symphony::IssueTrackers::FizzyClient.new(
      account_id: accounts(:"37s").external_account_id,
      board_ids: [ boards(:private).id ],
      active_states: [ "active", "review", "merging" ],
      terminal_states: [ "closed", "not_now" ]
    )

    issues = client.fetch_active_issues

    assert_equal [], issues
  end
end
