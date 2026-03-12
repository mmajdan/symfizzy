require "open3"
require "shellwords"

module Symphony
  class PullRequestCreator
    Result = Struct.new(:success, :url, :error, keyword_init: true)

    def initialize(repo:, base_branch:)
      @repo = repo
      @base_branch = base_branch
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
      with_workspace_git(workspace_path, "add -A")

      unless working_tree_dirty?(workspace_path)
        return Result.new(success: false, error: "No changes produced in workspace")
      end

      with_workspace_git(workspace_path, "commit -m #{Shellwords.escape(title)}")
      with_workspace_git(workspace_path, "push -u origin #{Shellwords.escape(branch)}")

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

      def run_command!(workspace_path, command)
        output, status = Open3.capture2e(command, chdir: workspace_path.to_s)

        if status.success?
          output
        else
          raise Error, "Command failed (#{command}): #{output.strip}"
        end
      end
  end
end
