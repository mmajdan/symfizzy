module Symphony
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class WorkflowError < Error; end
end
