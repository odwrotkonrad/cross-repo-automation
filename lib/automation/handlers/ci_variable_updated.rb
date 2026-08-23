##[>] 🤖🤖
module Automation
  module Handlers
    # CiVariableUpdated fans applied variables out: a build regen per rebuilt artifact, a record-only regen otherwise.
    module CiVariableUpdated
      def self.call(event, graph:)
        event.details['variables'].flat_map do |change|
          uri = graph.uri_for_var(change['key'])
          next [] unless uri

          key = graph.version_env_var(uri)
          rebuilt = graph.affected_artifacts(uri).filter_map { |a| graph.producer_of(a) }.uniq
          consumers = graph.affected(uri)
          (rebuilt & consumers).sort.map { |repo| job(repo, key, change, record_only: false) } +
            (consumers - rebuilt).map { |repo| job(repo, key, change, record_only: true) }
        end
      end

      def self.job(repo, key, change, record_only:)
        RegenPipeline::Job.new(repo: repo, key: key, tag: change['to'], prev: change['from'], record_only: record_only)
      end
    end
  end
end
##[<] 🤖🤖
