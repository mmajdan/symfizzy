namespace :symphony do
  desc "Run Symphony orchestrator"
  task :run, [ :workflow, :once ] => :environment do |_task, args|
    puts "DEBUG RAKE: Starting symphony:run task"
    workflow_paths = Symphony::WorkflowPathResolver.resolve_all(args[:workflow])
    puts "DEBUG RAKE: Found #{workflow_paths.size} workflow(s)"
    once = ActiveModel::Type::Boolean.new.cast(args[:once])
    logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new($stdout))
    logger.level = Logger::INFO
    errors = Queue.new

    threads = workflow_paths.map do |workflow_path|
      puts "DEBUG RAKE: Starting thread for #{workflow_path.basename}"
      Thread.new do
        Thread.current.report_on_exception = false

        logger.tagged("workflow=#{workflow_path.basename}") do
          puts "DEBUG RAKE: Creating service for #{workflow_path.basename}"
          Symphony::Service.new(workflow_path: workflow_path, logger: logger).run(once: once)
        end
      rescue => error
        puts "DEBUG RAKE: Error in thread: #{error.class}: #{error.message}"
        errors << error
      end
    end

    puts "DEBUG RAKE: Waiting for #{threads.size} thread(s) to complete"
    threads.each(&:join)
    puts "DEBUG RAKE: All threads completed"

    raise errors.pop unless errors.empty?
    puts "DEBUG RAKE: Task completed successfully"
  end
end
