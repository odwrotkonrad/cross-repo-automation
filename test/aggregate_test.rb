##[>] 🤖🤖
require 'minitest/autorun'
require 'automation'
require 'tmpdir'

class AggregateTest < Minitest::Test
  ASSETS = 'gitlab.com/konradodwrot/cross-repo/prose/assets'.freeze
  CHE = 'gitlab.com/konradodwrot/go-modules/che'.freeze
  CI_LINUX = 'registry/ci-linux'.freeze
  DIND = 'registry/ci-linux-dind'.freeze

  def produces(uri, type, var, version)
    { 'uri' => uri, 'type' => type, 'versionEnvVar' => var, 'version' => version }
  end

  def ref(uri, type, version = nil)
    { 'uri' => uri, 'type' => type }.merge(version ? { 'version' => version } : {})
  end

  def repos
    {
      'cross-repo/prose/assets' => {
        'downstream' => [produces(ASSETS, 'gitRepository', 'PROSE_ASSETS_REF', 'v0.0.60')],
        'dependsOn' => { ASSETS => [] }
      },
      'cross-repo/infra/oci-images' => {
        'downstream' => [produces(CI_LINUX, 'ociImage', 'OCI_IMAGES_CI_LINUX_REF', 'v0.0.124'),
                       produces(DIND, 'ociImage', 'OCI_IMAGES_CI_LINUX_DIND_REF', 'v0.0.124')],
        'upstream' => [ref(CHE, 'goModule', 'che/v0.0.94'), ref(ASSETS, 'gitRepository', 'v0.0.60')],
        'dependsOn' => { CI_LINUX => [ref(CHE, 'goModule')], DIND => [],
                         'ciEnv' => [ref(ASSETS, 'gitRepository')] }
      },
      'go-modules' => {
        'downstream' => [produces(CHE, 'goModule', 'GO_MODULES_CHE_REF', 'che/v0.0.94')],
        'dependsOn' => { CHE => [] }
      }
    }
  end

  def test_consistent_declarations_report_nothing
    assert_equal [], Automation::Aggregate.inconsistencies(repos)
  end

  def test_edges_merge_every_repos_depends_on_block
    assert_equal({ ASSETS => [], CHE => [], CI_LINUX => [CHE], DIND => [] }, Automation::Aggregate.edges(repos))
  end

  def test_reserved_keys_name_no_edge_and_still_cover_what_they_consume
    reserved = repos.merge(
      'notes' => {
        'upstream' => [ref(ASSETS, 'gitRepository', 'v0.0.60'), ref(CHE, 'goModule', 'che/v0.0.94')],
        'dependsOn' => { 'repoContents' => [ref(ASSETS, 'gitRepository')], 'devEnv' => [ref(CHE, 'goModule')] }
      }
    )
    assert_equal [], Automation::Aggregate.inconsistencies(reserved)
    assert_equal({ ASSETS => [], CHE => [], CI_LINUX => [CHE], DIND => [] }, Automation::Aggregate.edges(reserved))
  end

  def test_a_reference_to_an_undefined_uri_is_named
    broken = repos.merge('notes' => { 'upstream' => [ref('ghost://thing', 'gitRepository')] })
    assert_includes Automation::Aggregate.inconsistencies(broken),
                    'notes references ghost://thing, which no repo produces'
  end

  #[why] a dependsOn key names what the repo builds: keying an edge on a consumed artifact claims
  #   another repo's vertex and hangs upstreams off it
  def test_an_edge_keyed_on_an_artifact_the_repo_does_not_produce_is_named
    squatting = repos.merge('notes' => {
                              'downstream' => [produces('gitlab.com/konradodwrot/notes', 'gitRepository', 'NOTES_REF', 'v0.0.16')],
                              'dependsOn' => { 'gitlab.com/konradodwrot/notes' => [], CI_LINUX => [ref(CHE, 'goModule')] }
                            })
    assert_includes Automation::Aggregate.inconsistencies(squatting),
                    "notes keys a dependsOn edge on #{CI_LINUX}, which it does not produce"
  end

  def test_two_artifacts_sharing_one_variable_fail
    shared = repos.dup
    shared['cross-repo/infra/oci-images'] = Marshal.load(Marshal.dump(shared['cross-repo/infra/oci-images']))
    shared['cross-repo/infra/oci-images']['downstream'].find { |e| e['uri'] == DIND }['versionEnvVar'] = 'OCI_IMAGES_CI_LINUX_REF'
    found = Automation::Aggregate.inconsistencies(shared).grep(/versionEnvVar OCI_IMAGES_CI_LINUX_REF names 2 artifacts/)
    refute_empty found, 'a shared versionEnvVar must fail: this is the CI_IMAGES_REF bug'
  end

  def test_two_repos_defining_one_uri_differently_fail
    disagreeing = repos.merge('notes' => { 'downstream' => [produces(CHE, 'goModule', 'CHE_REF', 'che/v0.0.94')],
                                           'dependsOn' => { CHE => [] } })
    assert_includes Automation::Aggregate.inconsistencies(disagreeing).join("\n"), 'is defined differently by'
  end

  def test_a_cycle_is_named_with_its_full_path
    cyclic = repos.dup
    cyclic['go-modules'] = Marshal.load(Marshal.dump(cyclic['go-modules']))
    cyclic['go-modules']['dependsOn'] = { CHE => [ref(CI_LINUX, 'ociImage')] }
    cycle = Automation::Aggregate.inconsistencies(cyclic).grep(/^cycle: /).first
    refute_nil cycle
    assert_includes cycle, CHE
    assert_includes cycle, CI_LINUX
  end

  def test_undeclared_produced_artifacts_are_the_work_queue
    undeclared = repos.dup
    undeclared['cross-repo/prose/assets'] = { 'downstream' => [produces(ASSETS, 'gitRepository', 'PROSE_ASSETS_REF', 'v1')] }
    assert_equal ["cross-repo/prose/assets produces #{ASSETS} with no dependsOn entry"],
                 Automation::Aggregate.undeclared(undeclared)
  end

  def test_artifacts_hold_identity_and_no_versions
    doc = Automation::Aggregate.render(repos, kind: :artifacts)
    assert_includes doc, "  #{CHE}:\n    type: goModule\n    versionEnvVar: GO_MODULES_CHE_REF"
    refute_includes doc, "version:\n"
    refute_includes doc, "dependsOn:"
  end

  def test_latest_names_each_producers_published_version
    doc = Automation::Aggregate.render(repos, kind: :latest)
    assert_includes doc, "  #{CHE}: che/v0.0.94"
    assert_includes doc, "  #{ASSETS}: v0.0.60"
    refute_includes doc, "versionEnvVar"
  end

  def test_edges_carry_bare_uris_and_no_identity
    doc = Automation::Aggregate.render(repos, kind: :edges)
    assert_includes doc, "  #{CI_LINUX}:\n    - #{CHE}"
    assert_includes doc, "  #{DIND}: []"
    refute_includes doc, "version"
  end

  def test_current_mirrors_the_edge_structure_and_carries_versions
    current = Automation::Aggregate.render(repos, kind: :current)
    assert_includes current, "{artifact: #{CHE}, version: che/v0.0.94}"
    assert_equal Automation::Aggregate.render(repos, kind: :edges).lines.grep(/^  \S+:/).size,
                 current.lines.grep(/^  \S+:/).size, "current must mirror the edge structure"
  end

  #[why] the tracked lockfile is the only record of what a repo holds, so the graph's upstream
  #   versions must come from it and never from a version field left in the yml
  def test_upstream_versions_are_read_from_the_tracked_lockfile
    Dir.mktmpdir do |dir|
      Dir.mkdir(File.join(dir, '.repo'))
      File.write(File.join(dir, '.repo', 'upstream.yml'),
                 { 'upstream' => [{ 'uri' => CHE, 'type' => 'goModule', 'versionEnvVar' => 'GO_MODULES_CHE_REF',
                                    'version' => 'che/v0.0.1' }] }.to_yaml)
      File.write(File.join(dir, '.repo', 'upstream.env'), "# a comment\n\nGO_MODULES_CHE_REF=che/v0.0.94\n")

      doc = Automation::Aggregate.read_local(dir)
      assert_equal 'che/v0.0.94', doc.fetch('upstream').first.fetch('version')
    end
  end

  def test_an_upstream_key_absent_from_the_lockfile_reads_as_unversioned
    Dir.mktmpdir do |dir|
      Dir.mkdir(File.join(dir, '.repo'))
      File.write(File.join(dir, '.repo', 'upstream.yml'),
                 { 'upstream' => [{ 'uri' => CHE, 'type' => 'goModule', 'versionEnvVar' => 'GO_MODULES_CHE_REF' }] }.to_yaml)

      doc = Automation::Aggregate.read_local(dir)
      assert_nil doc.fetch('upstream').first.fetch('version')
    end
  end

  #[why] the collapsing aggregator stamped one version on every edge, hiding exactly the repo that lags
  def test_two_consumers_pinning_one_artifact_differently_both_survive
    lagging = repos.dup
    lagging["cross-repo/prose/assets"] = {
      "downstream" => [produces(ASSETS, "gitRepository", "PROSE_ASSETS_REF", "v0.0.60")],
      "upstream" => [ref(CHE, "goModule", "che/v0.0.90")],
      "dependsOn" => { ASSETS => [ref(CHE, "goModule")] }
    }
    current = Automation::Aggregate.render(lagging, kind: :current)
    assert_includes current, "  #{ASSETS}:\n    - {artifact: #{CHE}, version: che/v0.0.90}"
    assert_includes current, "  #{CI_LINUX}:\n    - {artifact: #{CHE}, version: che/v0.0.94}"
  end

  #[why] desired diverges from current the moment an operator raises a pin ahead of the merge that
  #   adopts it: that gap is the whole reason the two files exist apart
  def test_desired_versions_come_from_the_applied_variables_not_the_repos
    applied = { 'cross-repo/infra/oci-images' => { 'GO_MODULES_CHE_REF' => 'che/v0.0.95' },
                'group' => { 'GO_MODULES_CHE_REF' => 'che/v0.0.95' } }
    desired = Automation::Aggregate.render_desired(repos, applied)
    assert_includes desired, "  #{CI_LINUX}:\n    - {artifact: #{CHE}, version: che/v0.0.95}"
    assert_includes Automation::Aggregate.render(repos, kind: :current),
                    "  #{CI_LINUX}:\n    - {artifact: #{CHE}, version: che/v0.0.94}"
  end

  def test_a_consumer_with_no_project_variable_falls_back_to_the_group_scope
    desired = Automation::Aggregate.render_desired(repos, { 'group' => { 'GO_MODULES_CHE_REF' => 'che/v0.0.99' } })
    assert_includes desired, "{artifact: #{CHE}, version: che/v0.0.99}"
  end

  def test_retry_recovers_from_transient_errors_with_backoff
    pauses = []
    calls = 0
    res = nil
    capture_io do
      res = CrossRepo::Gitlab.with_retry('GET /x', attempts: 4, pause: 1, sleeper: ->(s) { pauses << s }) do
        calls += 1
        raise Net::OpenTimeout, 'boom' if calls < 3

        Net::HTTPOK.new('1.1', '200', 'OK')
      end
    end
    assert_equal 3, calls
    assert_equal [1, 2], pauses
    assert_kind_of Net::HTTPOK, res
  end
end
##[<] 🤖🤖
