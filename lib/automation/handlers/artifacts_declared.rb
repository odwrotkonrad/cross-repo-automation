##[>] 🤖🤖
module Automation
  module Handlers
    # ArtifactsDeclared answers a declaration change by re-deriving every aggregated graph file.
    module ArtifactsDeclared
      KINDS = %i[artifacts latest edges current].freeze

      def self.call(event, graph:)
        [RegenPipeline::GraphJob.new(kinds: KINDS, moved: "#{event.repo} declarations")]
      end
    end
  end
end
##[<] 🤖🤖
