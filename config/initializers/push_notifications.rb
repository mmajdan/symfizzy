Rails.autoloaders.main.on_load("Notification") do |notification, _abspath|
  notification.register_push_target(:web)
end
