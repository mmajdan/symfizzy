require "test_helper"
require "tmpdir"

class Symphony::WorkspaceManagerTest < ActiveSupport::TestCase
  test "bootstraps a git checkout in a new workspace" do
    Dir.mktmpdir do |root|
      workspace = Symphony::WorkspaceManager.new(root: root, source_repo_path: Rails.root).create_for_issue("CARD-9")

      assert_predicate workspace.path, :exist?
      assert_predicate workspace.path.join(".git"), :exist?
      assert_equal "CARD-9", workspace.workspace_key
      assert_equal true, workspace.created_now
    end
  end
end
