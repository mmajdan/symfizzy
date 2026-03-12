require "test_helper"

class Symphony::FizzyClientTest < ActiveSupport::TestCase
  test "returns active cards normalized as issues" do
    client = Symphony::IssueTrackers::FizzyClient.new(
      account_id: accounts(:"37s").external_account_id,
      active_states: [ "active" ],
      terminal_states: [ "closed", "not_now" ]
    )

    issues = client.fetch_active_issues

    assert issues.any?
    assert issues.all? { |issue| issue.state == "active" }
    assert issues.all? { |issue| issue.identifier.start_with?("CARD-") }
  end

  test "supports filtering by board ids" do
    client = Symphony::IssueTrackers::FizzyClient.new(
      account_id: accounts(:"37s").external_account_id,
      board_ids: [ boards(:private).id ],
      active_states: [ "active" ],
      terminal_states: [ "closed", "not_now" ]
    )

    issues = client.fetch_active_issues

    assert_equal [], issues
  end
end
