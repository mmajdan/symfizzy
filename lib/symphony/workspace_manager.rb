require "open3"
require "shellwords"

module Symphony
  class WorkspaceManager
    Workspace = Struct.new(:path, :workspace_key, :created_now, keyword_init: true)

    def initialize(root:, source_repo_path:)
      @root = Pathname(root)
      @source_repo_path = Pathname(source_repo_path)
    end

    def create_for_issue(identifier)
      key = sanitize_identifier(identifier)
      path = @root.join(key)
      created_now = !path.exist?

      @root.mkpath
      ensure_checkout(path)

      Workspace.new(path: path, workspace_key: key, created_now: created_now)
    end

    def remove_for_issue(identifier)
      path = @root.join(sanitize_identifier(identifier))
      path.rmtree if path.exist?
    end

    private
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
        output, status = Open3.capture2e("git remote get-url origin", chdir: @source_repo_path.to_s)

        if status.success?
          output.strip
        else
          @source_repo_path.to_s
        end
      end

      def sanitize_identifier(identifier)
        identifier.to_s.gsub(/[^A-Za-z0-9._-]/, "_")
      end
  end
end
