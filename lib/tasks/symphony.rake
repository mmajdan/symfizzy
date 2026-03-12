namespace :symphony do
  desc "Run Symphony orchestrator"
  task :run, [ :workflow, :once ] => :environment do |_task, args|
    workflow_path = args[:workflow].presence || Rails.root.join("WORKFLOW.md")
    once = ActiveModel::Type::Boolean.new.cast(args[:once])

    Symphony::Service.new(workflow_path: workflow_path).run(once: once)
  end
end
