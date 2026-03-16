require "json"

require "test_helper"

class Symphony::TelemetryLoggerTest < ActiveSupport::TestCase
  test "writes newline-delimited open telemetry style events" do
    Dir.mktmpdir do |dir|
      issue = Symphony::Issue.new(id: "123", identifier: "CARD-123", state: "active")
      log_path = Pathname(dir).join("telemetry.log")
      logger = Symphony::TelemetryLogger.new(log_path: log_path)

      logger.event(
        name: "symphony.issue.pickup",
        issue: issue,
        body: "Card picked up by orchestrator",
        attributes: { workflow: "default" }
      )

      payload = JSON.parse(log_path.read)

      assert_equal "INFO", payload["severity_text"]
      assert_equal "symphony.issue.pickup", payload["name"]
      assert_equal "Card picked up by orchestrator", payload["body"]
      assert_equal "123", payload.dig("attributes", "issue_id")
      assert_equal "CARD-123", payload.dig("attributes", "issue_identifier")
      assert_equal "active", payload.dig("attributes", "issue_state")
      assert_equal "default", payload.dig("attributes", "workflow")
      assert_equal 32, payload["trace_id"].length
      assert_equal 16, payload["span_id"].length
    end
  end
end
