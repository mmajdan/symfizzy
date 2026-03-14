require "rake"

require "test_helper"

class SymphonyRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    @task = Rake::Task["symphony:run"]
    @task.reenable
  end

  test "runs one Symphony service per workflow file when resolver returns multiple paths" do
    workflow_paths = [
      Pathname("/tmp/workflows/alpha.md"),
      Pathname("/tmp/workflows/beta.md")
    ]
    calls = Queue.new

    service_factory = lambda do |workflow_path:, logger:|
      Object.new.tap do |service|
        service.define_singleton_method(:run) do |once:|
          calls << { workflow_path: workflow_path, once: once, logger: logger }
        end
      end
    end

    original_resolve_all = Symphony::WorkflowPathResolver.method(:resolve_all)
    original_service_new = Symphony::Service.method(:new)

    Symphony::WorkflowPathResolver.singleton_class.send(:define_method, :resolve_all) do |*_args|
      workflow_paths
    end
    Symphony::Service.singleton_class.send(:define_method, :new, service_factory)

    @task.invoke(nil, "true")

    recorded_calls = 2.times.map { calls.pop }

    assert_equal workflow_paths.sort_by(&:to_s), recorded_calls.map { |call| call[:workflow_path] }.sort_by(&:to_s)
    assert_equal [ true, true ], recorded_calls.map { |call| call[:once] }
    assert recorded_calls.all? { |call| call[:logger].present? }
  ensure
    Symphony::WorkflowPathResolver.singleton_class.send(:define_method, :resolve_all, original_resolve_all)
    Symphony::Service.singleton_class.send(:define_method, :new, original_service_new)
  end
end
