ActiveSupport.on_load(:active_storage_attachment) do
  include Storage::AttachmentTracking
end

Rails.autoloaders.main.on_load("ActiveStorage::DiskController") do |controller, _abspath|
  controller.after_action only: :show do
    expires_in 5.minutes, public: true
  end
end

ActiveSupport.on_load(:action_text_content) do
  # Install our extensions after ActionText::Engine's
  ActiveSupport.on_load(:active_storage_blob) do
    # Ensure all <action-text-attachment>s have a "url" attribute that's a relative
    # path (for portability across host name changes, beta environments, etc).
    def to_rich_text_attributes(*)
      super.merge url: Rails.application.routes.url_helpers.polymorphic_url(self, only_path: true)
    end
  end
end

# Don't configure replica connections for ActiveStorage::Record.
# When ActiveStorage uses `connects_to`, it creates a separate connection pool
# from ApplicationRecord. This causes after_commit callbacks to fire in
# non-deterministic order - the Attachment's create_variants callback can fire
# before the User model's upload callback, causing FileNotFoundError when
# using `process: :immediately` for variants.
# See: https://github.com/rails/rails/issues/53694
ActiveSupport.on_load(:active_storage_record) do
  configure_replica_connections
end

module ActiveStorageControllerExtensions
  extend ActiveSupport::Concern

  included do
    before_action do
      # Add script_name so that Disk Service will generate correct URLs for uploads
      ActiveStorage::Current.url_options = {
        protocol: request.protocol,
        host: request.host,
        port: request.port,
        script_name: request.script_name
      }
    end
  end
end

module ActiveStorageDirectUploadsControllerExtensions
  extend ActiveSupport::Concern

  included do
    include Authentication
    include Authorization
    skip_forgery_protection if: :authenticate_by_bearer_token
  end
end

Rails.autoloaders.main.on_load("ActiveStorage::BaseController") do |controller, _abspath|
  controller.include ActiveStorageControllerExtensions unless controller < ActiveStorageControllerExtensions
end

Rails.autoloaders.main.on_load("ActiveStorage::DirectUploadsController") do |controller, _abspath|
  controller.include ActiveStorageDirectUploadsControllerExtensions unless controller < ActiveStorageDirectUploadsControllerExtensions
end
