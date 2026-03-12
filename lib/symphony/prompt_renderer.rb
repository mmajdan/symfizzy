module Symphony
  class PromptRenderer
    VARIABLE_PATTERN = /\{\{\s*([^}]+)\s*\}\}/.freeze

    def render(template:, issue:, attempt:, turn_number:, max_turns:)
      context = {
        "issue" => issue.to_template_payload,
        "attempt" => attempt,
        "turn_number" => turn_number,
        "max_turns" => max_turns
      }

      template.gsub(VARIABLE_PATTERN) do
        value = dig_value(context, Regexp.last_match(1).strip)

        if value.nil?
          raise WorkflowError, "Unknown template variable: #{Regexp.last_match(1).strip}"
        end

        value.to_s
      end
    end

    private
      def dig_value(payload, path)
        path.split(".").reduce(payload) do |cursor, key|
          if cursor.is_a?(Hash)
            cursor[key]
          else
            nil
          end
        end
      end
  end
end
