module Symphony
  TurnState = Struct.new(
    :issue_id,
    :current_turn,
    :workspace_path,
    :previous_outputs,
    :start_time,
    keyword_init: true
  )

  class TurnStateRegistry
    def initialize
      @states = {}
      @mutex = Mutex.new
    end

    def register(issue_id, workspace_path)
      @mutex.synchronize do
        @states[issue_id] = TurnState.new(
          issue_id: issue_id,
          current_turn: 1,
          workspace_path: workspace_path,
          previous_outputs: [],
          start_time: Time.current
        )
      end
    end

    def get(issue_id)
      @mutex.synchronize { @states[issue_id] }
    end

    def increment_turn(issue_id, output)
      @mutex.synchronize do
        state = @states[issue_id]
        return nil unless state

        state.current_turn += 1
        state.previous_outputs << output
        state
      end
    end

    def remove(issue_id)
      @mutex.synchronize { @states.delete(issue_id) }
    end

    def active?(issue_id)
      @mutex.synchronize { @states.key?(issue_id) }
    end

    def count
      @mutex.synchronize { @states.size }
    end
  end
end
