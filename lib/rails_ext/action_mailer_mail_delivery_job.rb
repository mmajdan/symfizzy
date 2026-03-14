ActiveSupport.on_load(:active_job) do
  ActionMailer::MailDeliveryJob.include SmtpDeliveryErrorHandling unless ActionMailer::MailDeliveryJob < SmtpDeliveryErrorHandling
end
