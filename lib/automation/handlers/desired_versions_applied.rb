##[>] 🤖🤖
module Automation
  module Handlers
    # DesiredVersionsApplied turns ci-variables' applied targets into the desired graph, the one file aggregation cannot derive.
    module DesiredVersionsApplied
      def self.call(event, graph:)
        [RegenPipeline::DesiredJob.new(versions: event.details.fetch('versions'), moved: "#{event.repo} applied")]
      end
    end
  end
end
##[<] 🤖🤖
