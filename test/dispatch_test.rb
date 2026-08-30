##[>] 🤖🤖
require 'minitest/autorun'
require 'automation'
require 'yaml'

class DispatchTest < Minitest::Test
  FIXTURE = File.expand_path('fixture', __dir__)
  CHE = 'gitlab.com/konradodwrot/go-modules/che'.freeze
  ASSETS = 'gitlab.com/konradodwrot/cross-repo/prose/assets'.freeze
  CONFIGS = 'gitlab.com/konradodwrot/tools-configs'.freeze
  CI_LINUX = 'registry/ci-linux'.freeze
  DIND = 'registry/ci-linux-dind'.freeze
  SOURCE = { 'project' => 'konradodwrot/x', 'pipeline' => '1', 'ref' => 'main', 'sha' => 'abc' }.freeze

  REPOS = {
    'go-modules' => { 'downstream' => [{ 'uri' => CHE, 'version' => 'che/v0.0.94' }] },
    'configs' => { 'downstream' => [{ 'uri' => CONFIGS, 'version' => 'v0.0.18' }],
                   'upstream' => [{ 'uri' => CHE, 'version' => 'che/v0.0.94' },
                                  { 'uri' => ASSETS, 'version' => 'v0.0.60' }] },
    'cross-repo/infra/oci-images' => {
      'downstream' => [{ 'uri' => CI_LINUX, 'version' => 'v0.0.124' }, { 'uri' => DIND, 'version' => 'v0.0.124' }],
      'upstream' => [{ 'uri' => CHE, 'version' => 'che/v0.0.94' }, { 'uri' => ASSETS, 'version' => 'v0.0.60' }]
    },
    'notes' => { 'upstream' => [{ 'uri' => ASSETS, 'version' => 'v0.0.60' }] }
  }.freeze

  def fixture_doc
    %w[artifacts.yml dependency-graph.yml].each_with_object({}) do |f, all|
      all.merge!(YAML.safe_load(File.read(File.join(FIXTURE, f))))
    end
  end

  def graph
    Automation::Graph.new(fixture_doc, repos: REPOS)
  end

  def event(type, details)
    Automation::Event.new(type: type, source: SOURCE, details: details)
  end

  def dispatch(*events)
    YAML.safe_load(Automation.dispatch(events, graph: graph))
  end

  def job_names(doc)
    doc.keys - ['stages', 'variables']
  end

  def test_a_release_triggers_the_variable_write_and_nothing_else
    doc = dispatch(event('artifact.released', { 'artifact' => { 'uri' => ASSETS, 'versionEnvVar' => 'PROSE_ASSETS_REF' },
                                                'version' => 'v0.0.61', 'prev' => 'v0.0.60' }))
    assert_equal ['vars:PROSE_ASSETS_REF'], job_names(doc)
  end

  #[why] a child pipeline checks out a clean tree, and shared/generic/ruby is gitignored (rendered from
  #   centralized/assets/generic), so a generated job that calls bin/automation without rendering it first dies
  #   with `cannot load such file -- artifact`. The parent jobs never hit this: `make aggregate`
  #   runs che, which renders the payload as a side effect
  def test_every_generated_job_renders_the_shared_payload_before_running
    doc = dispatch(event('artifact.released', { 'artifact' => { 'uri' => ASSETS, 'versionEnvVar' => 'PROSE_ASSETS_REF' },
                                                'version' => 'v0.0.61', 'prev' => 'v0.0.60' }))
    job_names(doc).each do |name|
      script = doc.fetch(name).fetch('script')
      assert_equal '[ -x shared/generic/ci/emit-events.zsh ] || ${CHE_BIN:-che} render-templates --profiles=genericSetup', script.first,
                   "#{name} must render shared/generic/ruby before calling bin/automation"
      assert script.any? { |s| s.start_with?('bin/automation') }, "#{name} runs no automation command"
    end
  end

  def test_an_upstream_nothing_depends_on_fans_out_record_only_regens
    doc = dispatch(event('ci-variable.updated',
                         { 'variables' => [{ 'key' => 'GRP_KO_VAR_PROSE_ASSETS_REF', 'from' => 'v0.0.60', 'to' => 'v0.0.61' }] }))
    scripts = job_names(doc).map { |n| doc[n]['script'].join }
    refute_empty scripts
    assert scripts.all? { |s| s.include?('--record-only') }, 'no consumer builds from prose/assets, so none may rebuild'
  end

  def test_a_che_release_rebuilds_its_dependents_and_records_the_rest
    doc = dispatch(event('ci-variable.updated',
                         { 'variables' => [{ 'key' => 'GRP_KO_VAR_GO_MODULES_CHE_REF', 'from' => 'che/v0.0.94', 'to' => 'che/v0.0.95' }] }))
    builds = job_names(doc).reject { |n| doc[n]['script'].join.include?('--record-only') }
    assert_includes builds, 'regen:cross-repo/infra/oci-images:GO_MODULES_CHE_REF'
    assert_includes builds, 'regen:configs:GO_MODULES_CHE_REF'
  end

  def test_a_produced_record_never_fans_out_a_release
    doc = dispatch(event('artifacts.produced', { 'repo' => 'notes', 'downstream' => [{ 'uri' => ASSETS, 'version' => 'v0.0.61' }] }))
    assert_equal ['graph:latest+current'], job_names(doc)
    assert_empty job_names(doc).grep(/^regen:/), 'artifacts.produced must emit zero regen jobs: it would loop'
  end

  def test_a_consumed_record_moves_the_current_graph_only
    doc = dispatch(event('artifacts.consumed', { 'repo' => 'notes', 'upstream' => [{ 'uri' => ASSETS, 'version' => 'v0.0.61' }] }))
    assert_equal ['graph:current'], job_names(doc)
  end

  def test_a_declaration_change_rederives_every_graph
    doc = dispatch(event('artifacts.declared', { 'repo' => 'notes' }))
    assert_equal ['graph:artifacts+latest+edges+current'], job_names(doc)
  end

  def test_applied_variables_write_the_desired_graph_alone
    doc = dispatch(event('desired-versions.applied',
                         { 'versions' => { 'configs' => { 'GO_MODULES_CHE_REF' => 'che/v0.0.95' } } }))
    assert_equal ['graph:desired'], job_names(doc)
    assert_includes doc['graph:desired']['script'].join, 'desired-write'
  end

  def test_one_commit_emitting_two_events_yields_one_pipeline
    doc = dispatch(event('artifacts.declared', { 'repo' => 'notes' }),
                   event('artifacts.consumed', { 'repo' => 'notes', 'upstream' => [] }))
    assert_equal ['graph:artifacts+latest+edges+current', 'graph:current'], job_names(doc)
  end

  def test_an_unmatched_variable_emits_the_no_op_job
    doc = dispatch(event('ci-variable.updated', { 'variables' => [{ 'key' => 'GRP_KO_VAR_UNKNOWN_REF', 'to' => 'v1' }] }))
    assert_equal ['no-op'], job_names(doc)
  end
end
##[<] 🤖🤖
