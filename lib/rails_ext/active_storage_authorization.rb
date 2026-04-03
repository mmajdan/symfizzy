ActiveSupport.on_load :active_storage_blob do
  def accessible_to?(user)
    attachments.includes(:record).any? { |attachment| attachment.accessible_to?(user) } || attachments.none?
  end

  def publicly_accessible?
    attachments.includes(:record).any? { |attachment| attachment.publicly_accessible? }
  end
end

ActiveSupport.on_load :active_storage_attachment do
  def accessible_to?(user)
    record.try(:accessible_to?, user)
  end

  def publicly_accessible?
    record.try(:publicly_accessible?)
  end
end

module ActiveStorage::Authorize
  extend ActiveSupport::Concern

  included do
    include Authentication
    # Ensure require_authentication runs after set_blob.
    skip_before_action :require_authentication
    before_action :require_authentication, :ensure_accessible, unless: :publicly_accessible_blob?
  end

  private
    def publicly_accessible_blob?
      @blob.publicly_accessible?
    end

    def ensure_accessible
      unless @blob.accessible_to?(Current.user)
        head :forbidden
      end
    end

    def http_cache_forever(public: false, &block)
      super(public: public && publicly_accessible_blob?, &block)
    end
end

[
  "ActiveStorage::Blobs::RedirectController",
  "ActiveStorage::Blobs::ProxyController",
  "ActiveStorage::Representations::RedirectController",
  "ActiveStorage::Representations::ProxyController"
].each do |controller_name|
  Rails.autoloaders.main.on_load(controller_name) do |controller, _abspath|
    controller.include ActiveStorage::Authorize unless controller < ActiveStorage::Authorize
  end
end
