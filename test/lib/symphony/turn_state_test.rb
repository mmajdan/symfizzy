require "test_helper"
require "symphony/turn_state"

class Symphony::TurnStateTest < ActiveSupport::TestCase
  test "registers new turn state" do
    registry = Symphony::TurnStateRegistry.new
    registry.register("issue-123", "/tmp/workspace-123")

    state = registry.get("issue-123")
    assert_equal "issue-123", state.issue_id
    assert_equal "/tmp/workspace-123", state.workspace_path
    assert_equal 1, state.current_turn
    assert_empty state.previous_outputs
    assert state.start_time
  end

  test "checks if issue has active turn state" do
    registry = Symphony::TurnStateRegistry.new
    assert_not registry.active?("issue-123")

    registry.register("issue-123", "/tmp/workspace-123")
    assert registry.active?("issue-123")
  end

  test "increments turn and stores output" do
    registry = Symphony::TurnStateRegistry.new
    registry.register("issue-123", "/tmp/workspace-123")

    state = registry.increment_turn("issue-123", "Output from turn 1")
    assert_equal 2, state.current_turn
    assert_equal [ "Output from turn 1" ], state.previous_outputs

    state = registry.increment_turn("issue-123", "Output from turn 2")
    assert_equal 3, state.current_turn
    assert_equal [ "Output from turn 1", "Output from turn 2" ], state.previous_outputs
  end

  test "returns nil when incrementing non-existent issue" do
    registry = Symphony::TurnStateRegistry.new
    state = registry.increment_turn("non-existent", "output")
    assert_nil state
  end

  test "removes turn state" do
    registry = Symphony::TurnStateRegistry.new
    registry.register("issue-123", "/tmp/workspace-123")
    assert registry.active?("issue-123")

    registry.remove("issue-123")
    assert_not registry.active?("issue-123")
    assert_nil registry.get("issue-123")
  end

  test "counts active turn states" do
    registry = Symphony::TurnStateRegistry.new
    assert_equal 0, registry.count

    registry.register("issue-1", "/tmp/workspace-1")
    assert_equal 1, registry.count

    registry.register("issue-2", "/tmp/workspace-2")
    assert_equal 2, registry.count

    registry.remove("issue-1")
    assert_equal 1, registry.count
  end

  test "is thread-safe" do
    registry = Symphony::TurnStateRegistry.new
    threads = []

    10.times do |i|
      threads << Thread.new do
        registry.register("issue-#{i}", "/tmp/workspace-#{i}")
      end
    end

    threads.each(&:join)
    assert_equal 10, registry.count
  end
end
