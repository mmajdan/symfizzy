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
      when "git checkout -B card-6"
        [ "", Status.new(0) ]
      when "git rev-parse HEAD"
        head_calls = commands.count { |candidate| candidate == "git rev-parse HEAD" }
        [ head_calls == 1 ? "abc123\n" : "def456\n", Status.new(0) ]
      when "git add -A"
        [ "", Status.new(0) ]
      when "git status --porcelain"
        [ "", Status.new(0) ]
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
      when "git checkout -B card-6", "git add -A"
        [ "", Status.new(0) ]
      when "git rev-parse HEAD"
        [ "abc123\n", Status.new(0) ]
      when "git status --porcelain"
        [ "", Status.new(0) ]
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

  test "updates existing PR when issue has pr_url (rework scenario)" do
    creator = Symphony::PullRequestCreator.new(repo: "org/repo", base_branch: "main")
    existing_pr_url = "https://github.com/org/repo/pull/42"
    issue = Symphony::Issue.new(
      identifier: "CARD-6",
      title: "PRD init",
      branch_name: "card-6",
      pr_url: existing_pr_url
    )
    commands = []

    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture2e) do |command, chdir:|
      commands << command

      case command
      when "git checkout -B card-6"
        [ "", Status.new(0) ]
      when "git rev-parse HEAD"
        head_calls = commands.count { |candidate| candidate == "git rev-parse HEAD" }
        [ head_calls == 1 ? "abc123\n" : "def456\n", Status.new(0) ]
      when "git add -A"
        [ "", Status.new(0) ]
      when "git status --porcelain"
        [ "M  file.txt\n", Status.new(0) ]
      when /git commit -m CARD-6/
        [ "", Status.new(0) ]
      when "git push -u origin card-6"
        [ "", Status.new(0) ]
      when /gh pr edit/
        [ "", Status.new(0) ]
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
    assert_equal existing_pr_url, result.url
    assert commands.any? { |cmd| cmd.include?("gh pr edit") }
    assert commands.any? { |cmd| cmd.include?(existing_pr_url) }
    assert_not commands.any? { |cmd| cmd.include?("gh pr create") }
  end

  test "rework returns no changes when branch head is unchanged" do
    creator = Symphony::PullRequestCreator.new(repo: "org/repo", base_branch: "main")
    issue = Symphony::Issue.new(
      identifier: "CARD-6",
      title: "PRD init",
      branch_name: "card-6",
      pr_url: "https://github.com/org/repo/pull/42"
    )

    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture2e) do |command, chdir:|
      case command
      when "git checkout -B card-6", "git add -A"
        [ "", Status.new(0) ]
      when "git rev-parse HEAD"
        [ "abc123\n", Status.new(0) ]
      when "git status --porcelain"
        [ "", Status.new(0) ]
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
