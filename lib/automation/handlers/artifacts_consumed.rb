##[>] 🤖🤖
module Automation
  module Handlers
    # ArtifactsConsumed records a consumer's adopted versions in the current graph and carries them into its ci-variables tfvars.
    module ArtifactsConsumed
      def self.call(event, graph:)
        moved = "#{event.repo} #{summary(event)}"
        [RegenPipeline::GraphJob.new(kinds: [:current], moved: moved), RegenPipeline::VarsJob.new(moved: moved)]
      end

      def self.summary(event)
        (event.details['upstream'] || []).map { |e| "#{e['artifact']} #{e['version']}" }.join(', ')
      end
    end
  end
end
##[<] 🤖🤖
