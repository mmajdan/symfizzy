require "test_helper"

class Symphony::PullRequestCreatorTest < ActiveSupport::TestCase
  Status = Struct.new(:exitstatus) do
    def success?
      exitstatus.zero?
    end
  end

  test "creates a PR when the branch already has committed changes" do
    creator = Symphony::PullRequestCreator.new(repo: "org/repo", base_branch: "main")
    issue = Symphony::Issue.new(identifier: "CARD-6", title: "PRD init", branch_name: "card-6")
    commands = []

    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture2e) do |command, chdir:|
      commands << command

      case command
      when "git rev-parse --verify origin/main"
        [ "origin/main\n", Status.new(0) ]
      when "git checkout -B card-6"
        [ "", Status.new(0) ]
      when "git add -A"
        [ "", Status.new(0) ]
      when "git status --porcelain"
        [ "", Status.new(0) ]
      when "git rev-list --count origin/main..HEAD"
        [ "3\n", Status.new(0) ]
      when "git push -u origin card-6"
        [ "", Status.new(0) ]
      when /gh pr create/
        [ "https://github.com/org/repo/pull/1\n", Status.new(0) ]
      else
        raise "Unexpected command: #{command}"
      end
    end

    begin
      result = creator.create_for(issue: issue, workspace_path: Rails.root)
    ensure
      Open3.define_singleton_method(:capture2e, original_capture2e)
    end

    assert_predicate result, :success
    assert_equal "https://github.com/org/repo/pull/1", result.url
    assert_not_includes commands, "git commit -m CARD-6:\\ PRD\\ init"
  end

  test "returns no changes when the branch has no committed or uncommitted changes" do
    creator = Symphony::PullRequestCreator.new(repo: "org/repo", base_branch: "main")
    issue = Symphony::Issue.new(identifier: "CARD-6", title: "PRD init", branch_name: "card-6")

    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture2e) do |command, chdir:|
      case command
      when "git rev-parse --verify origin/main"
        [ "origin/main\n", Status.new(0) ]
      when "git checkout -B card-6", "git add -A"
        [ "", Status.new(0) ]
      when "git status --porcelain"
        [ "", Status.new(0) ]
      when "git rev-list --count origin/main..HEAD"
        [ "0\n", Status.new(0) ]
      else
        raise "Unexpected command: #{command}"
      end
    end

    begin
      result = creator.create_for(issue: issue, workspace_path: Rails.root)
    ensure
      Open3.define_singleton_method(:capture2e, original_capture2e)
    end

    assert_not result.success
    assert_equal "No changes produced in workspace", result.error
  end
end
