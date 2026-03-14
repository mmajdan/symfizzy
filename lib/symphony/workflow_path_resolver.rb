module Symphony
  class WorkflowPathResolver
    ENVIRONMENT_KEY = "SYMPHONY_WORKFLOW_PATH".freeze
    FILENAME = "WORKFLOW.md".freeze

    def self.resolve(path = nil, env: ENV, root: Rails.root)
      new(path: path, env: env, root: root).resolve
    end

    def self.resolve_all(path = nil, env: ENV, root: Rails.root)
      new(path: path, env: env, root: root).resolve_all
    end

    def initialize(path:, env:, root:)
      @path = path
      @env = env
      @root = root
    end

    def resolve
      resolve_all.first
    end

    def resolve_all
      if @path.blank? && env_candidate_directory?
        workflow_paths_from_directory(environment_candidate)
      else
        [ resolved_candidate ]
      end
    end

    private
      def resolved_candidate
        candidate = explicit_or_environment_candidate || @root.join(FILENAME)
        candidate = Pathname(candidate).expand_path

        return candidate.join(FILENAME) if candidate.directory?

        candidate
      end

      def explicit_or_environment_candidate
        @path.presence || environment_candidate
      end

      def environment_candidate
        @env[ENVIRONMENT_KEY].presence
      end

      def env_candidate_directory?
        environment_candidate.present? && Pathname(environment_candidate).expand_path.directory?
      end

      def workflow_paths_from_directory(candidate)
        Pathname(candidate)
          .expand_path
          .children
          .select(&:file?)
          .sort_by(&:to_s)
      end
  end
end
