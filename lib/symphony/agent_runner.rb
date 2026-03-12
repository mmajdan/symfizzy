require "open3"

module Symphony
  class AgentRunner
    Result = Struct.new(:success, :status, :stdout, :stderr, :error, keyword_init: true)

    def initialize(command:)
      @command = command
    end

    def run(issue:, prompt:, workspace_path:)
      env = {
        "SYMPHONY_ISSUE_ID" => issue.id,
        "SYMPHONY_ISSUE_IDENTIFIER" => issue.identifier,
        "SYMPHONY_ISSUE_TITLE" => issue.title,
        "SYMPHONY_PROMPT" => prompt
      }

      stdout, stderr, status = Open3.capture3(env, @command, chdir: workspace_path.to_s)

      Result.new(success: status.success?, status: status.exitstatus, stdout: stdout, stderr: stderr)
    rescue => error
      Result.new(success: false, status: nil, stdout: "", stderr: "", error: error.message)
    end
  end
end
