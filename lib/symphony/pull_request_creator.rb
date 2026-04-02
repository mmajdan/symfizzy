require "open3"
require "shellwords"
require "uri"

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
      body = "Automated changes for #{issue.identifier} by Symphony."

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
      cmd = [
        "gh pr merge",
        "--repo", Shellwords.escape(repo),
        Shellwords.escape(pull_number),
        "--merge",
        "--delete-branch"
      ].join(" ")

      run_command!(workspace_path, cmd)
      Result.new(success: true, url: pr_url)
    rescue => error
      Result.new(success: false, error: error.message)
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
