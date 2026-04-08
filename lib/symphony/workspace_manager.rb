require "open3"
require "shellwords"
require "securerandom"
require "uri"

require "symphony/config"
require "symphony/workflow_loader"

module Symphony
  class WorkspaceManager
    Workspace = Struct.new(:path, :workspace_key, :created_now, keyword_init: true)

    def initialize(root:, workflow_path: nil, github_repo: nil, github_username: nil, github_token: nil)
      @root = Pathname(root)
      @workflow_path = Pathname(workflow_path) if workflow_path
      @github_repo = github_repo
      @github_username = github_username.to_s
      @github_token = github_token.to_s
    end

      def create_for_issue(identifier, branch_name: nil)
        @root.mkpath
        key, path = build_workspace_path(identifier)
        ensure_checkout(path)

        # If branch_name provided (e.g., from rework state), try to checkout existing branch
        if branch_name.present?
          checkout_branch_if_exists(path, branch_name)
        end

        Workspace.new(path: path, workspace_key: key, created_now: true)
      end

    def remove_for_issue(identifier)
      workspace_prefix = workspace_prefix_for(identifier)

      @root.children.each do |path|
        path.rmtree if path.basename.to_s.start_with?(workspace_prefix)
      end
    end

    def commit_changes(path, message)
      # Stage all changes
      add_output, add_status = Open3.capture2e("git add -A", chdir: path.to_s)
      return false unless add_status.success?

      # Check if there are changes to commit
      status_output, status_status = Open3.capture2e("git status --porcelain", chdir: path.to_s)
      return true if status_output.blank? # Nothing to commit

      # Commit with message
      commit_output, commit_status = Open3.capture2e(
        "git commit -m #{Shellwords.escape(message)}",
        chdir: path.to_s
      )

      commit_status.success?
    end

    private
      def build_workspace_path(identifier)
        prefix = workspace_prefix_for(identifier)

        loop do
          key = "#{prefix}-#{SecureRandom.hex(6)}"
          path = @root.join(key)

          return [ key, path ] unless path.exist?
        end
      end

      def ensure_checkout(path)
        if git_checkout?(path)
          true
        elsif path.exist? && path.children.any?
          raise Error, "Workspace exists but is not a git checkout: #{path}"
        else
          path.mkpath
          clone_repository_into(path)
        end
      end

      def git_checkout?(path)
        path.join(".git").exist?
      end

      def clone_repository_into(path)
        source = source_clone_url
        output, status = Open3.capture2e("git clone #{Shellwords.escape(source)} .", chdir: path.to_s)

        if status.success?
          output
        else
          raise Error, "Failed to clone workspace from #{source}: #{output.strip}"
        end
      end

      def source_clone_url
        repo = workflow_repo.presence || @github_repo
        raise Error, "GitHub repo is not configured in WORKFLOW.md" if repo.blank?

        return repo if local_path_repo?(repo)
        return repo if remote_clone_url?(repo)

        clone_url = "https://github.com/#{repo}.git"
        with_credentials(clone_url)
      end

      def with_credentials(url)
        return url unless (credential_pair = credential_pair())

        uri = URI.parse(url)
        uri.user = credential_pair.first
        uri.password = credential_pair.last
        uri.to_s
      end

      def credential_pair
        username = workflow_username.presence || @github_username
        token = workflow_token.presence || @github_token
        username = username.to_s.strip
        token = token.to_s.strip
        username.empty? || token.empty? ? nil : [ username, token ]
      end

      def workflow_repo
        workflow_config&.github_repo
      end

      def workflow_username
        workflow_config&.github_username
      end

      def workflow_token
        workflow_config&.github_token
      end

      def workflow_config
        return unless @workflow_path
        @workflow_config ||= begin
          loader = WorkflowLoader.new(path: @workflow_path)
          Config.new(loader.load.config)
        end
      end

      def local_path_repo?(repo = nil)
        source_repo = repo.presence || workflow_repo.presence || @github_repo
        source_repo.to_s.start_with?("/", ".", "~") || Pathname(source_repo.to_s).exist?
      end

      def remote_clone_url?(repo = nil)
        clone_target = repo.presence || workflow_repo.presence || @github_repo
        clone_target.to_s.match?(/\Ahttps?:\/\//) || clone_target.to_s.start_with?("git@")
      end

      def sanitize_identifier(identifier)
        identifier.to_s.gsub(/[^A-Za-z0-9._-]/, "_")
      end

      def workspace_prefix_for(identifier)
        sanitize_identifier(identifier)
      end

      def checkout_branch_if_exists(path, branch_name)
        sanitized_branch = sanitize_identifier(branch_name)

        # Check if branch exists on origin
        output, status = Open3.capture2e("git ls-remote --heads origin #{Shellwords.escape(sanitized_branch)}", chdir: path.to_s)

        if status.success? && output.include?(sanitized_branch)
          @logger&.info("WorkspaceManager: Found existing branch '#{sanitized_branch}' on origin, checking out...")

          # Fetch the branch
          fetch_output, fetch_status = Open3.capture2e("git fetch origin #{Shellwords.escape(sanitized_branch)}:#{Shellwords.escape(sanitized_branch)}", chdir: path.to_s)

          if fetch_status.success?
            # Checkout the branch
            checkout_output, checkout_status = Open3.capture2e("git checkout #{Shellwords.escape(sanitized_branch)}", chdir: path.to_s)

            if checkout_status.success?
              @logger&.info("WorkspaceManager: Successfully checked out branch '#{sanitized_branch}'")
              true
            else
              @logger&.warn("WorkspaceManager: Failed to checkout branch '#{sanitized_branch}': #{checkout_output.strip}")
              false
            end
          else
            @logger&.warn("WorkspaceManager: Failed to fetch branch '#{sanitized_branch}': #{fetch_output.strip}")
            false
          end
        else
          @logger&.info("WorkspaceManager: Branch '#{sanitized_branch}' does not exist on origin, staying on default branch")
          false
        end
      end
  end
end
