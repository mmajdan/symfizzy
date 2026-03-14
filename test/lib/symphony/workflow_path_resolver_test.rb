require "test_helper"

class Symphony::WorkflowPathResolverTest < ActiveSupport::TestCase
  test "resolve_all uses SYMPHONY_WORKFLOW_PATH when it points to a workflow file" do
    Dir.mktmpdir do |root|
      workflow_path = Pathname(root).join("custom.md")

      resolved = Symphony::WorkflowPathResolver.resolve_all(nil, env: { "SYMPHONY_WORKFLOW_PATH" => workflow_path.to_s }, root: Rails.root)

      assert_equal [ workflow_path ], resolved
    end
  end

  test "uses SYMPHONY_WORKFLOW_PATH when it points to a workflow file" do
    Dir.mktmpdir do |root|
      workflow_path = Pathname(root).join("custom.md")

      resolved = Symphony::WorkflowPathResolver.resolve(nil, env: { "SYMPHONY_WORKFLOW_PATH" => workflow_path.to_s }, root: Rails.root)

      assert_equal workflow_path, resolved
    end
  end

  test "resolve_all uses every file from SYMPHONY_WORKFLOW_PATH when it points to a directory" do
    Dir.mktmpdir do |root|
      workflow_dir = Pathname(root)
      workflow_a = workflow_dir.join("alpha.md")
      workflow_b = workflow_dir.join("beta.md")
      nested_dir = workflow_dir.join("nested")

      workflow_b.write("beta")
      workflow_a.write("alpha")
      nested_dir.mkpath
      nested_dir.join("ignored.md").write("ignored")

      resolved = Symphony::WorkflowPathResolver.resolve_all(nil, env: { "SYMPHONY_WORKFLOW_PATH" => workflow_dir.to_s }, root: Rails.root)

      assert_equal [ workflow_a, workflow_b ], resolved
    end
  end

  test "resolve still uses the first workflow file from SYMPHONY_WORKFLOW_PATH when it points to a directory" do
    Dir.mktmpdir do |root|
      workflow_dir = Pathname(root)
      workflow_a = workflow_dir.join("alpha.md")
      workflow_b = workflow_dir.join("beta.md")

      workflow_b.write("beta")
      workflow_a.write("alpha")

      resolved = Symphony::WorkflowPathResolver.resolve(nil, env: { "SYMPHONY_WORKFLOW_PATH" => workflow_dir.to_s }, root: Rails.root)

      assert_equal workflow_a, resolved
    end
  end

  test "explicit workflow argument takes precedence over SYMPHONY_WORKFLOW_PATH" do
    Dir.mktmpdir do |root|
      explicit_path = Pathname(root).join("explicit.md")

      resolved = Symphony::WorkflowPathResolver.resolve(explicit_path.to_s, env: { "SYMPHONY_WORKFLOW_PATH" => "/tmp/ignored" }, root: Rails.root)

      assert_equal explicit_path, resolved
    end
  end

  test "resolve_all keeps explicit workflow argument precedence over SYMPHONY_WORKFLOW_PATH directory" do
    Dir.mktmpdir do |root|
      explicit_path = Pathname(root).join("explicit.md")
      explicit_path.write("explicit")

      resolved = Symphony::WorkflowPathResolver.resolve_all(explicit_path.to_s, env: { "SYMPHONY_WORKFLOW_PATH" => "/tmp/ignored" }, root: Rails.root)

      assert_equal [ explicit_path ], resolved
    end
  end

  test "falls back to Rails.root WORKFLOW.md" do
    custom_root = Pathname("/tmp/symphony-root")

    resolved = Symphony::WorkflowPathResolver.resolve(nil, env: {}, root: custom_root)

    assert_equal custom_root.join("WORKFLOW.md"), resolved
  end

  test "resolve_all falls back to Rails.root WORKFLOW.md" do
    custom_root = Pathname("/tmp/symphony-root")

    resolved = Symphony::WorkflowPathResolver.resolve_all(nil, env: {}, root: custom_root)

    assert_equal [ custom_root.join("WORKFLOW.md") ], resolved
  end
end
