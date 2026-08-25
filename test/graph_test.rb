##[>] 🤖🤖
require 'minitest/autorun'
require 'automation'
require 'yaml'

class GraphTest < Minitest::Test
  FIXTURE = File.expand_path('fixture', __dir__)
  CHE = 'gitlab.com/konradodwrot/go-modules/che'.freeze
  ASSETS = 'gitlab.com/konradodwrot/cross-repo/prose/assets'.freeze
  CONFIGS = 'gitlab.com/konradodwrot/configs'.freeze
  CI_LINUX = 'registry/ci-linux'.freeze
  DIND = 'registry/ci-linux-dind'.freeze

  REPOS = {
    'go-modules' => { 'downstream' => [{ 'uri' => CHE, 'version' => 'che/v0.0.94' }] },
    'configs' => { 'downstream' => [{ 'uri' => CONFIGS, 'version' => 'v0.0.18' }],
                   'upstream' => [{ 'uri' => CHE, 'version' => 'che/v0.0.94' },
                                  { 'uri' => ASSETS, 'version' => 'v0.0.60' }] },
    'cross-repo/infra/oci-images' => {
      'downstream' => [{ 'uri' => CI_LINUX, 'version' => 'v0.0.124' }, { 'uri' => DIND, 'version' => 'v0.0.124' }],
      'upstream' => [{ 'uri' => CHE, 'version' => 'che/v0.0.94' }]
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

  def test_reads_the_declared_variable_rather_than_deriving_it
    assert_equal 'OCI_IMAGES_CI_LINUX_REF', graph.version_env_var(CI_LINUX)
    assert_equal 'OCI_IMAGES_CI_LINUX_DIND_REF', graph.version_env_var(DIND)
  end

  def test_maps_a_scoped_variable_key_back_to_its_artifact
    assert_equal ASSETS, graph.uri_for_var('GRP_KO_VAR_PROSE_ASSETS_REF')
    assert_equal ASSETS, graph.uri_for_var('REPO_VAR_PROSE_ASSETS_REF')
    assert_nil graph.uri_for_var('GRP_KO_VAR_NOTHING_REF')
  end

  def test_affected_lists_consumers_excluding_the_producer
    assert_equal ['configs', 'cross-repo/infra/oci-images'], graph.affected(CHE)
    assert_equal %w[notes], graph.affected(ASSETS) - ['configs']
  end

  def test_affected_artifacts_scopes_a_release_to_what_depends_on_it
    assert_equal [CONFIGS, CI_LINUX], graph.affected_artifacts(CHE)
    refute_includes graph.affected_artifacts(CHE), DIND, 'ci-linux-dind declares no che dependency'
  end

  def test_an_upstream_nothing_is_built_from_rebuilds_nothing
    assert_equal [], graph.affected_artifacts(ASSETS)
    assert_equal graph.affected(ASSETS).sort, graph.record_only(ASSETS).sort
  end

  def test_record_only_excludes_repos_that_actually_rebuild
    refute_includes graph.record_only(CHE), 'cross-repo/infra/oci-images'
  end

  def test_producer_of_answers_which_repo_publishes_an_artifact
    assert_equal 'go-modules', graph.producer_of(CHE)
    assert_equal 'cross-repo/infra/oci-images', graph.producer_of(DIND)
  end

  def test_pins_name_the_project_variable_each_consumer_reads
    keys = graph.pins_for(ASSETS).map(&:var_key).uniq
    assert_equal ['REPO_VAR_PROSE_ASSETS_REF'], keys
  end

  def test_no_ci_variable_vertex_survives
    doc = fixture_doc
    refute_includes doc['artifacts'].values.map { |a| a['type'] }, 'ci-variable'
    assert_empty doc['artifacts'].keys.grep(%r{/ci-var/})
  end
end
##[<] 🤖🤖
