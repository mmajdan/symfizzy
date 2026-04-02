require "test_helper"

class Symphony::ServiceTest < ActiveSupport::TestCase
  class FakeOrchestrator
    attr_reader :calls

    def initialize
      @calls = []
    end

    def tick
      @calls << :tick
    end

    def wait_until_idle
      @calls << :wait_until_idle
    end
  end

  test "run once waits for orchestrator to become idle" do
    orchestrator = FakeOrchestrator.new
    service = Symphony::Service.allocate
    service.instance_variable_set(:@logger, Rails.logger)

    service.singleton_class.define_method(:build_orchestrator) do
      orchestrator
    end

    service.run(once: true)

    assert_equal [ :tick, :wait_until_idle ], orchestrator.calls
  end
end
