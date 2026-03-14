require "test_helper"
require "tmpdir"

class Symphony::WorkspaceManagerTest < ActiveSupport::TestCase
  test "bootstraps a git checkout in a new workspace" do
    Dir.mktmpdir do |root|
      workflow_path = write_workflow(root, repo: Rails.root.to_s)
      workspace = Symphony::WorkspaceManager.new(root: root, workflow_path: workflow_path).create_for_issue("CARD-9")

      assert_predicate workspace.path, :exist?
      assert_predicate workspace.path.join(".git"), :exist?
      assert_match(/\ACARD-9-[0-9a-f]{12}\z/, workspace.workspace_key)
      assert_equal true, workspace.created_now
    end
  end

  test "creates a separate workspace for each issue run" do
    Dir.mktmpdir do |root|
      workflow_path = write_workflow(root, repo: Rails.root.to_s)
      manager = Symphony::WorkspaceManager.new(root: root, workflow_path: workflow_path)

      first_workspace = manager.create_for_issue("CARD-9")
      second_workspace = manager.create_for_issue("CARD-9")

      assert_not_equal first_workspace.path, second_workspace.path
      assert_not_equal first_workspace.workspace_key, second_workspace.workspace_key
      assert_predicate first_workspace.path.join(".git"), :exist?
      assert_predicate second_workspace.path.join(".git"), :exist?
    end
  end

  test "remove_for_issue removes every workspace created for that issue" do
    Dir.mktmpdir do |root|
      workflow_path = write_workflow(root, repo: Rails.root.to_s)
      manager = Symphony::WorkspaceManager.new(root: root, workflow_path: workflow_path)

      first_workspace = manager.create_for_issue("CARD-9")
      second_workspace = manager.create_for_issue("CARD-9")
      other_workspace = manager.create_for_issue("CARD-10")

      manager.remove_for_issue("CARD-9")

      assert_not_predicate first_workspace.path, :exist?
      assert_not_predicate second_workspace.path, :exist?
      assert_predicate other_workspace.path, :exist?
    end
  end

  test "builds github clone url from owner slash repo" do
    Dir.mktmpdir do |root|
      workflow_path = write_workflow(root, repo: "mmajdan/amelia")
      manager = Symphony::WorkspaceManager.new(root: root, workflow_path: workflow_path)

      assert_equal "https://github.com/mmajdan/amelia.git", manager.send(:source_clone_url)
    end
  end

  test "applies workflow username and token when cloning" do
    Dir.mktmpdir do |root|
      workflow_path = write_workflow(root, repo: "mmajdan/amelia", username: "user", token: "secret")
      manager = Symphony::WorkspaceManager.new(root: root, workflow_path: workflow_path)

      assert_match(%r{https://user:secret@github.com/mmajdan/amelia.git}, manager.send(:source_clone_url))
    end
  end

  private

  def write_workflow(root, repo:, username: nil, token: nil)
    workflow_path = File.join(root, "WORKFLOW.md")
    File.write(workflow_path, <<~YAML)
      ---
      github:
        repo: "#{repo}"
        #{ "username: \"#{username}\"" if username }
        #{ "github_token: \"#{token}\"" if token }
      ---
      prompt
    YAML
    workflow_path
  end
end
