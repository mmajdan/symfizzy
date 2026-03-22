require "test_helper"

class Symphony::FizzyClientTest < ActiveSupport::TestCase
  test "returns active cards normalized as issues" do
    board = boards(:writebook)
    todo_column = board.columns.create!(
      name: "todo",
      color: "var(--color-card-1)",
      position: 97,
      account: accounts(:"37s")
    )
    in_progress_column = board.columns.create!(
      name: "IN PROGRESS",
      color: "var(--color-card-2)",
      position: 98,
      account: accounts(:"37s")
    )
    cards(:buy_domain).update!(column: todo_column)
    cards(:logo).update!(column: in_progress_column)

    client = Symphony::IssueTrackers::FizzyClient.new(
      account_id: accounts(:"37s").external_account_id,
      active_states: [ "active", "review", "merging" ],
      terminal_states: [ "closed", "not_now" ]
    )

    issues = client.fetch_active_issues

    assert issues.any?
    assert issues.all? { |issue| issue.identifier.start_with?("CARD-") }
    assert_includes issues.map(&:id), cards(:buy_domain).id
    assert_includes issues.map(&:id), cards(:logo).id
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

  test "maps cards outside active and terminal columns to not_now" do
    maybe_column = boards(:writebook).columns.create!(
      name: "Maybe",
      color: "var(--color-card-1)",
      position: 101,
      account: accounts(:"37s")
    )
    maybe_card = cards(:layout)
    maybe_card.update!(column: maybe_column)

    client = Symphony::IssueTrackers::FizzyClient.new(
      account_id: accounts(:"37s").external_account_id,
      active_states: [ "active" ],
      terminal_states: [ "closed", "not_now", "done" ]
    )

    assert_equal "not_now", client.fetch_issue(maybe_card.id).state
    assert_not_includes client.fetch_active_issues.map(&:id), maybe_card.id
    assert_includes client.fetch_terminal_issues.map(&:id), maybe_card.id
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

  test "moves failed active issue back to retryable todo column" do
    todo_column = boards(:writebook).columns.create!(
      name: "ToDo",
      color: "var(--color-card-1)",
      position: 97,
      account: accounts(:"37s")
    )
    client = Symphony::IssueTrackers::FizzyClient.new(
      account_id: accounts(:"37s").external_account_id,
      active_states: [ "active" ],
      active_column_names: [ "ToDo", "Rework" ],
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

    client.transition_to_retry(card.id, previous_state: "active")

    assert_equal todo_column, card.reload.column
  end

  test "moves failed rework issue back to retryable rework column" do
    rework_column = boards(:writebook).columns.create!(
      name: "Rework",
      color: "var(--color-card-1)",
      position: 97,
      account: accounts(:"37s")
    )
    client = Symphony::IssueTrackers::FizzyClient.new(
      account_id: accounts(:"37s").external_account_id,
      active_states: [ "active", "rework" ],
      active_column_names: [ "ToDo", "Rework" ],
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

    client.transition_to_retry(card.id, previous_state: "rework")

    assert_equal rework_column, card.reload.column
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

  test "can restrict active issues to selected column names" do
    board = boards(:writebook)
    todo_column = board.columns.create!(
      name: "ToDo",
      color: "var(--color-card-1)",
      position: 97,
      account: accounts(:"37s")
    )
    in_progress_column = board.columns.create!(
      name: "In Progress",
      color: "var(--color-card-2)",
      position: 98,
      account: accounts(:"37s")
    )
    review_column = board.columns.create!(
      name: "Review",
      color: "var(--color-card-3)",
      position: 99,
      account: accounts(:"37s")
    )

    todo_card = cards(:buy_domain)
    in_progress_card = cards(:logo)
    review_card = cards(:layout)

    todo_card.update!(column: todo_column)
    in_progress_card.update!(column: in_progress_column)
    review_card.update!(column: review_column)

    client = Symphony::IssueTrackers::FizzyClient.new(
      account_id: accounts(:"37s").external_account_id,
      board_ids: [ board.id ],
      active_states: [ "active" ],
      active_column_names: [ "ToDo", "In Progress" ],
      terminal_states: [ "closed", "not_now", "done" ]
    )

    issues = client.fetch_active_issues

    assert_includes issues.map(&:id), todo_card.id
    assert_includes issues.map(&:id), in_progress_card.id
    assert_not_includes issues.map(&:id), review_card.id
  end

  test "does not include postponed cards in active issues even when active columns are configured" do
    board = boards(:writebook)
    todo_column = board.columns.create!(
      name: "To do",
      color: "var(--color-card-1)",
      position: 97,
      account: accounts(:"37s")
    )
    postponed_card = cards(:buy_domain)
    postponed_card.update!(column: todo_column)

    Current.set(account: accounts(:"37s"), user: users(:david)) do
      postponed_card.postpone
    end

    client = Symphony::IssueTrackers::FizzyClient.new(
      account_id: accounts(:"37s").external_account_id,
      board_ids: [ board.id ],
      active_states: [ "active" ],
      active_column_names: [ "To do", "In Progress" ],
      terminal_states: [ "closed", "not_now", "done" ]
    )

    assert_equal "not_now", client.fetch_issue(postponed_card.id).state
    assert_not_includes client.fetch_active_issues.map(&:id), postponed_card.id
    assert_includes client.fetch_terminal_issues.map(&:id), postponed_card.id
  end
end
