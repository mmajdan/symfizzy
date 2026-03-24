require "test_helper"

class Symphony::PromptRendererTest < ActiveSupport::TestCase
  test "renders nil issue values as empty strings" do
    issue = Symphony::Issue.new(identifier: "CARD-1", description: nil, priority: nil)

    rendered = Symphony::PromptRenderer.new.render(
      template: "Description: {{ issue.description }} | Priority: {{ issue.priority }}",
      issue: issue,
      attempt: 0,
      turn_number: 1,
      max_turns: 20
    )

    assert_equal "Description:  | Priority: ", rendered
  end

  test "raises for unknown variables" do
    issue = Symphony::Issue.new(identifier: "CARD-1")

    error = assert_raises(Symphony::WorkflowError) do
      Symphony::PromptRenderer.new.render(
        template: "Unknown {{ issue.missing }}",
        issue: issue,
        attempt: 0,
        turn_number: 1,
        max_turns: 20
      )
    end

    assert_match "Unknown template variable", error.message
  end

  test "renders issue steps" do
    issue = Symphony::Issue.new(identifier: "CARD-1", steps: [ "[todo] First step", "[done] Second step" ])

    rendered = Symphony::PromptRenderer.new.render(
      template: "Steps: {{ issue.steps }}",
      issue: issue,
      attempt: 0,
      turn_number: 1,
      max_turns: 20
    )

    assert_equal "Steps: [todo] First step\n[done] Second step", rendered
  end
end
