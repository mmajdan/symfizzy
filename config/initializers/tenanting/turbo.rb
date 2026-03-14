module TurboStreamsJobExtensions
  extend ActiveSupport::Concern

  class_methods do
    def render_format(format, **rendering)
      if Current.account.present?
        ApplicationController.renderer.new(script_name: Current.account.slug).render(formats: [ format ], **rendering)
      else
        super
      end
    end
  end
end

Rails.autoloaders.main.on_load("Turbo::StreamsChannel") do |channel, _abspath|
  channel.singleton_class.prepend TurboStreamsJobExtensions unless channel.singleton_class < TurboStreamsJobExtensions
end
