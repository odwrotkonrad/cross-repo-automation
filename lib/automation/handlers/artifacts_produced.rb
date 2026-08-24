##[>] 🤖🤖
module Automation
  module Handlers
    # ArtifactsProduced records a publication in the latest and current graphs, fanning out nothing: the loop-breaking rule.
    module ArtifactsProduced
      def self.call(event, graph:)
        [RegenPipeline::GraphJob.new(kinds: %i[latest current], moved: "#{event.repo} #{summary(event)}")]
      end

      def self.summary(event)
        (event.details['produces'] || []).map { |e| "#{e['artifact']} #{e['version']}" }.join(', ')
      end
    end
  end
end
##[<] 🤖🤖
