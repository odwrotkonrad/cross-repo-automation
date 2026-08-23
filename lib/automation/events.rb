##[>] 🤖🤖
module Automation
  # Events is the single catalogue of every event automation accepts: its details and why it exists.
  module Events
    Entry = Struct.new(:type, :details, :purpose, keyword_init: true)

    CATALOGUE = [
      Entry.new(type: 'artifact.released', details: %w[artifact version],
                purpose: 'a producer published a version: raise the variables that carry it'),
      Entry.new(type: 'ci-variable.updated', details: %w[variables],
                purpose: 'applied variables moved: fan out to each consumer of what moved'),
      Entry.new(type: 'artifacts.consumed', details: %w[repo consumes],
                purpose: "a consumer's rendered versions moved: re-derive the current graph"),
      Entry.new(type: 'artifacts.produced', details: %w[repo produces],
                purpose: 'a producer recorded its own version: re-derive the current graph, never fan out'),
      Entry.new(type: 'desired-versions.applied', details: %w[versions],
                purpose: 'ci-variables applied its targets: re-derive the desired graph from them'),
      Entry.new(type: 'artifacts.declared', details: %w[repo],
                purpose: 'a declaration changed: re-derive every aggregated graph file')
    ].freeze

    #[why] renamed in this change, kept one release so in-flight producers do not break
    ALIASES = { 'release.published' => 'artifact.released', 'ci-var.changed' => 'ci-variable.updated' }.freeze

    BY_TYPE = CATALOGUE.to_h { |e| [e.type, e] }.freeze

    def self.types
      BY_TYPE.keys
    end

    # Maps a legacy type onto its current name, raising on one the catalogue does not define.
    def self.resolve(type)
      resolved = ALIASES.fetch(type, type)
      raise ArgumentError, "unknown event type #{type.inspect}" unless BY_TYPE.key?(resolved)

      resolved
    end

    def self.required_details(type)
      BY_TYPE.fetch(resolve(type)).details
    end
  end
end
##[<] 🤖🤖
