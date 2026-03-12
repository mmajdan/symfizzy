require "test_helper"

class Symphony::WorkflowLoaderTest < ActiveSupport::TestCase
  test "loads workflow with front matter" do
    file = Tempfile.new([ "workflow", ".md" ])
    file.write <<~MD
      ---
      tracker:
        kind: fizzy
        account_id: "$FIZZY_ACCOUNT_ID"
      ---
      Work on {{ issue.identifier }}
    MD
    file.close

    workflow = Symphony::WorkflowLoader.new(path: file.path).load

    assert_equal "fizzy", workflow.config.dig("tracker", "kind")
    assert_equal "Work on {{ issue.identifier }}", workflow.prompt_template
  ensure
    file.unlink
  end

  test "loads workflow without front matter" do
    file = Tempfile.new([ "workflow", ".md" ])
    file.write "Just prompt"
    file.close

    workflow = Symphony::WorkflowLoader.new(path: file.path).load

    assert_equal({}, workflow.config)
    assert_equal "Just prompt", workflow.prompt_template
  ensure
    file.unlink
  end
end
