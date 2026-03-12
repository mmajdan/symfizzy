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
    review_card = cards(:shipping)
    review_card.update!(column: columns(:writebook_review))

    merging_column = boards(:writebook).columns.create!(
      name: "Merging",
      color: "var(--color-card-2)",
      position: 99,
      account: accounts(:"37s")
    )
    merging_card = cards(:layout)
    merging_card.update!(column: merging_column)

    client = Symphony::IssueTrackers::FizzyClient.new(
      account_id: accounts(:"37s").external_account_id,
      active_states: [ "active", "review", "merging" ],
      terminal_states: [ "closed", "not_now" ]
    )

    states = client.fetch_active_issues.index_by(&:id)

    assert_equal "review", states[review_card.id].state
    assert_equal "merging", states[merging_card.id].state
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
