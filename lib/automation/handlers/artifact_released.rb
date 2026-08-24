##[>] 🤖🤖
module Automation
  module Handlers
    # ArtifactReleased answers a producer release by triggering the ci-variables apply that raises its version.
    module ArtifactReleased
      def self.call(event, graph:)
        artifact = event.details.fetch('artifact')
        uri = artifact.is_a?(Hash) ? artifact.fetch('uri') : artifact
        key = (artifact.is_a?(Hash) && artifact['versionEnvVar']) || graph.version_env_var(uri)
        raise ArgumentError, "#{uri} names no version-env-var in the graph" unless key

        [RegenPipeline::VarsJob.new(artifact: uri, key: key, tag: event.details['version'] || event.tag,
                                    prev: event.details['prev'])]
      end
    end
  end
end
##[<] 🤖🤖
