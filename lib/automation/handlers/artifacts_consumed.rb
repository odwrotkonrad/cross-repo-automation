##[>] 🤖🤖
module Automation
  module Handlers
    # ArtifactsConsumed records a consumer's adopted versions in the current graph: convergence moves here.
    module ArtifactsConsumed
      def self.call(event, graph:)
        [RegenPipeline::GraphJob.new(kinds: [:current], moved: "#{event.repo} #{summary(event)}")]
      end

      def self.summary(event)
        (event.details['consumes'] || []).map { |e| "#{e['artifact']} #{e['version']}" }.join(', ')
      end
    end
  end
end
##[<] 🤖🤖
