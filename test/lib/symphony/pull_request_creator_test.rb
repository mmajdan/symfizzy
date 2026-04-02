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
    Open3.define_singleton_method(:capture2e) do |*args, chdir:|
      command = args.last
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
    Open3.define_singleton_method(:capture2e) do |*args, chdir:|
      command = args.last
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
    Open3.define_singleton_method(:capture2e) do |*args, chdir:|
      command = args.last
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
      when /gh api --method PATCH repos\/org\/repo\/pulls\/42/
        [ '{"url":"https://github.com/org/repo/pull/42"}', Status.new(0) ]
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
    api_command = commands.find { |cmd| cmd.start_with?("gh api --method PATCH") }
    assert api_command.present?
    assert_includes api_command, "repos/org/repo/pulls/42"
    assert_includes api_command, "title\\=CARD-6"
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
    Open3.define_singleton_method(:capture2e) do |*args, chdir:|
      command = args.last
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

  test "passes configured github token to gh commands via GH_TOKEN" do
    creator = Symphony::PullRequestCreator.new(repo: "org/repo", base_branch: "main", github_token: "secret-token")
    issue = Symphony::Issue.new(identifier: "CARD-6", title: "PRD init", branch_name: "card-6")
    gh_envs = []
    rev_parse_calls = 0

    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture2e) do |*args, chdir:|
      env, command = args.length == 2 ? args : [ {}, args.first ]
      gh_envs << env if command.start_with?("gh ")

      case command
      when "git checkout -B card-6"
        [ "", Status.new(0) ]
      when "git rev-parse HEAD"
        rev_parse_calls += 1
        [ rev_parse_calls == 1 ? "abc123\n" : "def456\n", Status.new(0) ]
      when "git add -A"
        [ "", Status.new(0) ]
      when "git status --porcelain"
        [ "M  README.md\n", Status.new(0) ]
      when /git commit -m CARD-6/
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
    assert_equal [({ "GH_TOKEN" => "secret-token" })], gh_envs
  end

  test "adds PR comment with configured github token" do
    creator = Symphony::PullRequestCreator.new(repo: "org/repo", base_branch: "main", github_token: "secret-token")
    commands = []
    gh_envs = []

    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture2e) do |*args, chdir:|
      env, command = args.length == 2 ? args : [ {}, args.first ]
      commands << command
      gh_envs << env if command.start_with?("gh ")

      case command
      when /gh pr comment --repo org\/repo 42 --body /
        [ "commented\n", Status.new(0) ]
      else
        raise "Unexpected command: #{command}"
      end
    end

    begin
      result = creator.add_comment(
        pr_url: "https://github.com/org/repo/pull/42",
        body: "Implementation summary\n\nUpdated README.md",
        workspace_path: Rails.root
      )
    ensure
      Open3.define_singleton_method(:capture2e, original_capture2e)
    end

    assert_equal true, result
    assert_equal({ "GH_TOKEN" => "secret-token" }, gh_envs.first)
    assert_match(/gh pr comment --repo org\/repo 42 --body /, commands.first)
  end

  test "merges PR with configured github token" do
    creator = Symphony::PullRequestCreator.new(repo: "org/repo", base_branch: "main", github_token: "secret-token")
    commands = []
    gh_envs = []

    original_capture2e = Open3.method(:capture2e)
    Open3.define_singleton_method(:capture2e) do |*args, chdir:|
      env, command = args.length == 2 ? args : [ {}, args.first ]
      commands << command
      gh_envs << env if command.start_with?("gh ")

      case command
      when "gh pr merge --repo org/repo 42 --merge --delete-branch"
        [ "merged\n", Status.new(0) ]
      else
        raise "Unexpected command: #{command}"
      end
    end

    begin
      result = creator.merge(
        pr_url: "https://github.com/org/repo/pull/42",
        workspace_path: Rails.root
      )
    ensure
      Open3.define_singleton_method(:capture2e, original_capture2e)
    end

    assert_predicate result, :success
    assert_equal "https://github.com/org/repo/pull/42", result.url
    assert_equal({ "GH_TOKEN" => "secret-token" }, gh_envs.first)
    assert_equal "gh pr merge --repo org/repo 42 --merge --delete-branch", commands.first
  end
end
