module Symphony
  class PromptRenderer
    VARIABLE_PATTERN = /\{\{\s*([^}]+)\s*\}\}/.freeze

    def render(template:, issue:, attempt:, turn_number:, max_turns:, previous_turn_output: nil)
      context = {
        "issue" => issue.to_template_payload,
        "attempt" => attempt,
        "turn_number" => turn_number,
        "max_turns" => max_turns,
        "previous_turn_output" => previous_turn_output
      }

      template.gsub(VARIABLE_PATTERN) do
        path = Regexp.last_match(1).strip
        found, value = dig_value(context, path)

        unless found
          raise WorkflowError, "Unknown template variable: #{path}"
        end

        stringify_value(value)
      end
    end

    private
      def dig_value(payload, path)
        path.split(".").reduce([ true, payload ]) do |(found, cursor), key|
          break [ false, nil ] unless found && cursor.is_a?(Hash)
          break [ false, nil ] unless cursor.key?(key)

          [ true, cursor[key] ]
        end
      end

      def stringify_value(value)
        case value
        when Array
          value.map(&:to_s).join("\n")
        else
          value.to_s
        end
      end
  end
end
