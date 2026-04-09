require "open3"
require "shellwords"
require "uri"
require "json"

module Symphony
  class PullRequestCreator
    Result = Struct.new(:success, :url, :error, keyword_init: true)

    def initialize(repo:, base_branch:, github_token: nil)
      @repo = repo
      @base_branch = base_branch
      @github_token = github_token.to_s
    end

    def create_for(issue:, workspace_path:)
      unless git_repository?(workspace_path)
        return Result.new(success: false, error: "Workspace is not a git repository")
      end

      if @repo.blank?
        return Result.new(success: false, error: "GitHub repo is not configured")
      end

      branch = issue.branch_name.presence || "symphony/#{issue.identifier.downcase}"
      title = "#{issue.identifier}: #{issue.title}"
      description = issue.description.presence || "Automated changes for #{issue.identifier} by Symphony."
      body = "#{description}\n\nplease @codex review the PR"

      with_workspace_git(workspace_path, "checkout -B #{Shellwords.escape(branch)}")
      original_head = current_head(workspace_path)
      with_workspace_git(workspace_path, "add -A")

      if working_tree_dirty?(workspace_path)
        with_workspace_git(workspace_path, "commit -m #{Shellwords.escape(title)}")
      end

      unless new_commit_produced?(workspace_path, original_head)
        return Result.new(success: false, error: "No changes produced in workspace")
      end

      with_workspace_git(workspace_path, "push -u origin #{Shellwords.escape(branch)}")

      if issue.pr_url.present?
        update_existing_pr!(workspace_path, pr_url: issue.pr_url, title: title, body: body)
        Result.new(success: true, url: issue.pr_url)
      else
        # Create new PR
        cmd = [
          "gh pr create",
          "--repo", Shellwords.escape(@repo),
          "--base", Shellwords.escape(@base_branch),
          "--head", Shellwords.escape(branch),
          "--title", Shellwords.escape(title),
          "--body", Shellwords.escape(body)
        ].join(" ")

        output = run_command!(workspace_path, cmd)
        url = output.lines.last&.strip.presence

        if url.present?
          Result.new(success: true, url: url)
        else
          Result.new(success: false, error: "GitHub PR creation did not return a URL")
        end
      end
    rescue => error
      Result.new(success: false, error: error.message)
    end

    def add_comment(pr_url:, body:, workspace_path:)
      repo, pull_number = parse_pr_url!(pr_url)
      cmd = [
        "gh pr comment",
        "--repo", Shellwords.escape(repo),
        Shellwords.escape(pull_number),
        "--body", Shellwords.escape(body)
      ].join(" ")

      run_command!(workspace_path, cmd)
      true
    end

    def merge(pr_url:, workspace_path:)
      repo, pull_number = parse_pr_url!(pr_url)

      # Step 1: Check if PR is mergeable
      mergeable = check_mergeable(repo, pull_number, workspace_path)

      if mergeable
        # Simple merge
        perform_merge(repo, pull_number, workspace_path, pr_url)
      else
        # Step 2: Attempt conflict resolution
        resolve_result = resolve_conflicts(repo, pull_number, workspace_path)

        if resolve_result[:success]
          # Retry merge after conflict resolution
          perform_merge(repo, pull_number, workspace_path, pr_url)
        else
          Result.new(success: false, error: "Cannot merge PR: #{resolve_result[:error]}")
        end
      end
    rescue => error
      Result.new(success: false, error: error.message)
    end

    def check_mergeable(repo, pull_number, workspace_path)
      cmd = [
        "gh pr view",
        "--repo", Shellwords.escape(repo),
        Shellwords.escape(pull_number),
        "--json", "mergeStateStatus"
      ].join(" ")

      output = run_command!(workspace_path, cmd)
      data = JSON.parse(output)
      merge_state = data["mergeStateStatus"].to_s.downcase

      # CLEAN means no conflicts, ready to merge
      merge_state == "clean"
    rescue
      false
    end

    def resolve_conflicts(repo, pull_number, workspace_path)
      begin
        # Get PR details
        cmd = [
          "gh pr view",
          "--repo", Shellwords.escape(repo),
          Shellwords.escape(pull_number),
          "--json", "headRefName,baseRefName"
        ].join(" ")

        output = run_command!(workspace_path, cmd)
        data = JSON.parse(output)
        head_branch = data["headRefName"]
        base_branch = data["baseRefName"] || @base_branch

        # Fetch latest base branch
        run_command!(workspace_path, "git fetch origin #{Shellwords.escape(base_branch)}")

        # Checkout PR branch
        run_command!(workspace_path, "git fetch origin #{Shellwords.escape(head_branch)}")
        run_command!(workspace_path, "git checkout -B #{Shellwords.escape(head_branch)} origin/#{Shellwords.escape(head_branch)}")

        # Attempt merge of base branch into PR branch
        merge_output, merge_status = Open3.capture2e(
          command_env,
          "git merge origin/#{Shellwords.escape(base_branch)} --no-edit",
          chdir: workspace_path.to_s
        )

        if merge_status.success?
          # No conflicts, push the merge commit
          run_command!(workspace_path, "git push origin #{Shellwords.escape(head_branch)}")
          return { success: true }
        end

        # Conflicts exist - try to resolve by keeping both changes
        conflict_files = get_conflict_files(workspace_path)

        if conflict_files.empty?
          return { success: false, error: "Merge failed but no conflict files found" }
        end

        # For each conflicted file, resolve by accepting both changes
        conflict_files.each do |file|
          resolve_conflict_file(workspace_path, file)
        end

        # Complete the merge
        run_command!(workspace_path, "git add -A")
        run_command!(workspace_path, "git commit -m \"Resolve merge conflicts\" --no-edit")
        run_command!(workspace_path, "git push origin #{Shellwords.escape(head_branch)}")

        { success: true }
      rescue => error
        { success: false, error: error.message }
      end
    end

    def get_conflict_files(workspace_path)
      output, status = Open3.capture2e("git diff --name-only --diff-filter=U", chdir: workspace_path.to_s)
      return [] unless status.success?

      output.lines.map(&:strip).reject(&:empty?)
    end

    def resolve_conflict_file(workspace_path, file)
      file_path = File.join(workspace_path, file)
      return unless File.exist?(file_path)

      content = File.read(file_path)

      # Remove conflict markers, keeping both versions
      # This is a simple resolution strategy - accept both changes
      resolved = content.gsub(/^<<<<<<<[^\n]*\n(.*?)^=======\n(.*?)^>>>>>>>[^\n]*\n?/m) do
        "#{Regexp.last_match(1)}#{Regexp.last_match(2)}"
      end

      File.write(file_path, resolved)
    end

    def perform_merge(repo, pull_number, workspace_path, pr_url)
      cmd = [
        "gh pr merge",
        "--repo", Shellwords.escape(repo),
        Shellwords.escape(pull_number),
        "--merge",
        "--delete-branch"
      ].join(" ")

      run_command!(workspace_path, cmd)
      Result.new(success: true, url: pr_url)
    end

    private
      def git_repository?(workspace_path)
        git_directory = Pathname(workspace_path).join(".git")

        git_directory.exist?
      end

      def working_tree_dirty?(workspace_path)
        status = run_command!(workspace_path, "git status --porcelain")
        status.present?
      end

      def with_workspace_git(workspace_path, args)
        run_command!(workspace_path, "git #{args}")
      end

      def new_commit_produced?(workspace_path, original_head)
        current_head(workspace_path) != original_head
      end

      def current_head(workspace_path)
        run_command!(workspace_path, "git rev-parse HEAD").strip
      end

      def update_existing_pr!(workspace_path, pr_url:, title:, body:)
        repo, pull_number = parse_pr_url!(pr_url)
        cmd = [
          "gh api",
          "--method", "PATCH",
          Shellwords.escape("repos/#{repo}/pulls/#{pull_number}"),
          "-f", Shellwords.escape("title=#{title}"),
          "-f", Shellwords.escape("body=#{body}")
        ].join(" ")

        run_command!(workspace_path, cmd)
      end

      def parse_pr_url!(pr_url)
        uri = URI.parse(pr_url)
        match = uri.path.match(%r{\A/([^/]+/[^/]+)/pull/(\d+)\z})

        raise Error, "Unsupported GitHub PR URL: #{pr_url}" unless match

        [ match[1], match[2] ]
      rescue URI::InvalidURIError
        raise Error, "Unsupported GitHub PR URL: #{pr_url}"
      end

      def remote_base_branch(workspace_path)
        if remote_branch_exists?(workspace_path, "origin/#{@base_branch}")
          "origin/#{@base_branch}"
        else
          @base_branch
        end
      end

      def remote_branch_exists?(workspace_path, branch)
        _output, status = Open3.capture2e("git rev-parse --verify #{Shellwords.escape(branch)}", chdir: workspace_path.to_s)
        status.success?
      end

      def run_command!(workspace_path, command)
        output, status = Open3.capture2e(command_env, command, chdir: workspace_path.to_s)

        if status.success?
          output
        else
          raise Error, "Command failed (#{command}): #{output.strip}"
        end
      end

      def command_env
        return {} if @github_token.blank?

        { "GH_TOKEN" => @github_token }
      end
  end
end
