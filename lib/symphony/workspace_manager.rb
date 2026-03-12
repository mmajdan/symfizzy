module Symphony
  class WorkspaceManager
    Workspace = Struct.new(:path, :workspace_key, :created_now, keyword_init: true)

    def initialize(root:)
      @root = Pathname(root)
    end

    def create_for_issue(identifier)
      key = sanitize_identifier(identifier)
      path = @root.join(key)
      created_now = !path.exist?

      path.mkpath

      Workspace.new(path: path, workspace_key: key, created_now: created_now)
    end

    def remove_for_issue(identifier)
      path = @root.join(sanitize_identifier(identifier))
      path.rmtree if path.exist?
    end

    private
      def sanitize_identifier(identifier)
        identifier.to_s.gsub(/[^A-Za-z0-9._-]/, "_")
      end
  end
end
