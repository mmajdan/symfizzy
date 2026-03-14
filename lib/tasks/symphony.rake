namespace :symphony do
  desc "Run Symphony orchestrator"
  task :run, [ :workflow, :once ] => :environment do |_task, args|
    workflow_paths = Symphony::WorkflowPathResolver.resolve_all(args[:workflow])
    once = ActiveModel::Type::Boolean.new.cast(args[:once])
    logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new($stdout))
    logger.level = Logger::INFO
    errors = Queue.new

    workflow_paths.map do |workflow_path|
      Thread.new do
        Thread.current.report_on_exception = false

        logger.tagged("workflow=#{workflow_path.basename}") do
          Symphony::Service.new(workflow_path: workflow_path, logger: logger).run(once: once)
        end
      rescue => error
        errors << error
      end
    end.each(&:join)

    raise errors.pop unless errors.empty?
  end
end
