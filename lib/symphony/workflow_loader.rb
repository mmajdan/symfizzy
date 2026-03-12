require "yaml"

module Symphony
  class WorkflowLoader
    FRONT_MATTER_BOUNDARY = "---".freeze

    WorkflowDefinition = Struct.new(:config, :prompt_template, keyword_init: true)

    def initialize(path:)
      @path = Pathname(path)
    end

    def load
      raise WorkflowError, "Workflow file not found: #{@path}" unless @path.exist?

      body = @path.read

      if body.start_with?("#{FRONT_MATTER_BOUNDARY}\n")
        parse_with_front_matter(body)
      else
        WorkflowDefinition.new(config: {}, prompt_template: body.strip)
      end
    end

    private
      def parse_with_front_matter(body)
        _, raw_config, prompt_template = body.split(/^---\s*$\n?/, 3)

        if prompt_template.nil?
          raise WorkflowError, "Invalid WORKFLOW.md: missing closing front matter boundary"
        end

        parsed = YAML.safe_load(raw_config, permitted_classes: [], aliases: false)
        config = parsed.is_a?(Hash) ? parsed : {}

        WorkflowDefinition.new(config: config.deep_stringify_keys, prompt_template: prompt_template.strip)
      rescue Psych::SyntaxError => error
        raise WorkflowError, "Invalid YAML in WORKFLOW.md: #{error.message}"
      end
  end
end
