require "json"
require "digest"
require "securerandom"

module Symphony
  class TelemetryLogger
    def initialize(log_path:, logger: Rails.logger)
      @log_path = Pathname(log_path)
      @logger = logger
      @mutex = Mutex.new
    end

    def event(name:, issue: nil, body: nil, severity_text: "INFO", attributes: {})
      payload = {
        timestamp: Time.current.utc.iso8601(6),
        severity_text: severity_text,
        name: name,
        body: body,
        trace_id: trace_id_for(issue),
        span_id: SecureRandom.hex(8),
        attributes: default_attributes(issue).merge(attributes)
      }.compact

      write(payload)
    rescue => error
      @logger.error("Symphony telemetry write failed: #{error.class}: #{error.message}")
    end

    private
      def write(payload)
        @mutex.synchronize do
          @log_path.dirname.mkpath
          @log_path.open("a") { |file| file.puts(payload.to_json) }
        end
      end

      def trace_id_for(issue)
        return unless issue

        Digest::SHA256.hexdigest(issue.id.to_s)[0, 32]
      end

      def default_attributes(issue)
        return {} unless issue

        {
          issue_id: issue.id,
          issue_identifier: issue.identifier,
          issue_state: issue.state
        }.compact
      end
  end
end
