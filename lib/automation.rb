##[>] 🤖🤖
$LOAD_PATH.unshift(File.expand_path('../shared/generic/ruby', __dir__))

require 'artifact'
require 'declaration'
require 'event'
require 'gitlab'

require_relative 'automation/shell'
require_relative 'automation/events'
require_relative 'automation/graph'
require_relative 'automation/regen_pipeline'
require_relative 'automation/handlers/artifact_released'
require_relative 'automation/handlers/ci_variable_updated'
require_relative 'automation/handlers/artifacts_declared'
require_relative 'automation/handlers/artifacts_consumed'
require_relative 'automation/handlers/artifacts_produced'
require_relative 'automation/handlers/desired_versions_applied'
require_relative 'automation/aggregate'
require_relative 'automation/cycle'
require_relative 'automation/repo_writer'
require_relative 'automation/graph_writer'
require_relative 'automation/ci_vars_writer'
require_relative 'automation/regen'
require_relative 'automation/regen_runner'
require_relative 'automation/sweep'

# Automation turns one CI event batch into the child pipeline that answers it.
module Automation
  Event = CrossRepo::Event
  Artifact = CrossRepo::Artifact
  Declaration = CrossRepo::Declaration

  HANDLERS = {
    'artifact.released' => Handlers::ArtifactReleased,
    'ci-variable.updated' => Handlers::CiVariableUpdated,
    'artifacts.declared' => Handlers::ArtifactsDeclared,
    'artifacts.consumed' => Handlers::ArtifactsConsumed,
    'artifacts.produced' => Handlers::ArtifactsProduced,
    'desired-versions.applied' => Handlers::DesiredVersionsApplied
  }.freeze

  # Returns the child pipeline YAML answering every event in +events+, merged into one job list.
  def self.dispatch(events, graph:)
    batch = Array(events)
    jobs = batch.flat_map { |event| HANDLERS.fetch(event.type).call(event, graph: graph) }
    RegenPipeline.render(jobs, empty_reason: "#{batch.map(&:type).join(' ')}: no affected downstreams")
  end
end
##[<] 🤖🤖
