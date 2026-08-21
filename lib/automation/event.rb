##[>] 🤖🤖
require 'json'

module Automation
  # Event is one parsed AUTOMATION_EVENT: a known type, where it came from, the sender's details.
  Event = Struct.new(:type, :source, :details, keyword_init: true) do
    REQUIRED_DETAILS = {
      'release.published' => %w[producer artifact tag],
      'ci-var.changed' => %w[variables]
    }.freeze
    SOURCE_FIELDS = %w[project pipeline ref sha].freeze

    # Parses the JSON event, raising on an unknown type or a missing field.
    def self.parse(json)
      doc = JSON.parse(json)
      type = doc.fetch('type') { raise ArgumentError, 'event has no type' }
      required = REQUIRED_DETAILS.fetch(type) { raise ArgumentError, "unknown event type #{type.inspect}" }
      source = doc.fetch('source') { raise ArgumentError, 'event has no source' }
      details = doc.fetch('details') { raise ArgumentError, 'event has no details' }
      missing = (SOURCE_FIELDS - source.keys).map { |k| "source.#{k}" } +
                (required - details.keys).map { |k| "details.#{k}" }
      raise ArgumentError, "#{type} event missing #{missing.join(', ')}" unless missing.empty?

      new(type: type, source: source, details: details)
    end

    def summary
      case type
      when 'release.published' then "#{details['producer']} #{details['tag']}"
      when 'ci-var.changed' then details['variables'].map { |v| v['key'] }.join(',')
      end
    end
  end
end
##[<] 🤖🤖
