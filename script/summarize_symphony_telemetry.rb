#!/usr/bin/env ruby

require "json"
require "pathname"
require "time"
require "tmpdir"

DEFAULT_PATH = File.join(Dir.tmpdir, "symphony_workspaces", "telemetry.log")

path = Pathname(ARGV[0] || DEFAULT_PATH)

abort("Telemetry log not found: #{path}") unless path.exist?

events = path.each_line.filter_map do |line|
  next if line.strip.empty?

  JSON.parse(line, symbolize_names: true)
end

puts "Telemetry file: #{path}"
puts "Total events: #{events.size}"
puts

grouped = events.group_by { |event| event[:trace_id] }

grouped.each_value do |trace_events|
  trace_events.sort_by! { |event| Time.iso8601(event[:timestamp]) }
end

grouped.sort_by { |_trace_id, trace_events| Time.iso8601(trace_events.first[:timestamp]) }.each do |trace_id, trace_events|
  first = trace_events.first
  last = trace_events.last
  issue = first.fetch(:attributes, {})
  started_at = Time.iso8601(first[:timestamp])
  ended_at = Time.iso8601(last[:timestamp])
  duration = (ended_at - started_at).round(3)
  event_names = trace_events.map { |event| event[:name] }

  puts "Trace #{trace_id}"
  puts "  Issue: #{issue[:issue_identifier]} (#{issue[:issue_state]})"
  puts "  Events: #{trace_events.size}"
  puts "  Duration: #{duration}s"
  puts "  Sequence: #{event_names.join(' -> ')}"

  prompt_event = trace_events.find { |event| event[:name] == "symphony.agent.prompt" }
  if prompt_event
    prompt = prompt_event.dig(:attributes, :prompt).to_s
    prompt_preview = prompt.lines.first(8).join.strip
    puts "  Prompt preview: #{prompt_preview}"
  end

  pr_event = trace_events.reverse.find { |event| event[:name] == "symphony.pull_request.created" }
  if pr_event
    puts "  PR: #{pr_event.dig(:attributes, :pr_url)}"
  end

  puts
end
