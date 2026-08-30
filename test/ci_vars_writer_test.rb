##[>] 🤖🤖
require 'minitest/autorun'
require 'automation'

class CiVarsWriterTest < Minitest::Test
  MISC = 'gitlab.com/konradodwrot/cross-repo/misc'.freeze
  CHE = 'gitlab.com/konradodwrot/go-modules/che'.freeze

  def repos
    {
      'cross-repo/misc' => {
        'downstream' => [{ 'uri' => MISC, 'type' => 'gitRepository', 'versionEnvVar' => 'MISC_REF',
                         'version' => 'v0.0.30' }],
        'dependsOn' => { MISC => [] }
      },
      'go-modules' => {
        'downstream' => [{ 'uri' => CHE, 'type' => 'goModule', 'versionEnvVar' => 'GO_MODULES_CHE_REF',
                         'version' => 'che/v0.0.96' }],
        'upstream' => [{ 'uri' => MISC, 'type' => 'gitRepository', 'version' => 'v0.0.30' }],
        'dependsOn' => { CHE => [] }
      }
    }
  end

  def producers(released = {})
    Automation::CiVarsWriter.files(repos, released).fetch('live/producers/generated.auto.tfvars')
  end

  #[why] the whole point of the release event: a producer's artifacts-produced.yml renders its
  #   version from the group variable, which still names the version published BEFORE this release.
  #   Regenerating from declarations alone pins the stale value and the release reaches nobody
  def test_the_released_version_wins_over_the_producers_own_declaration
    assert_match(/^MISC_REF\s+= "v0\.0\.37"$/, producers(MISC => 'v0.0.37'))
    refute_includes producers(MISC => 'v0.0.37'), '"v0.0.30"'
  end

  def test_artifacts_this_release_did_not_move_keep_their_declared_version
    doc = producers(MISC => 'v0.0.37')

    assert_match(%r{^GO_MODULES_CHE_REF\s+= "che/v0\.0\.96"$}, doc)
  end

  def test_with_no_release_every_version_comes_from_the_declarations
    assert_match(/^MISC_REF\s+= "v0\.0\.30"$/, producers)
  end

  def current(vars)
    Automation::CiVarsWriter.files(repos, {}, vars).fetch('live/producers/generated.auto.tfvars')
  end

  def test_a_pin_the_file_already_holds_is_never_lowered
    assert_match(/^MISC_REF\s+= "v0\.0\.44"$/, current('MISC_REF' => 'v0.0.44'))
  end

  def test_a_higher_declaration_wins_over_the_held_pin
    assert_match(/^MISC_REF\s+= "v0\.0\.30"$/, current('MISC_REF' => 'v0.0.29'))
  end

  def test_the_released_version_wins_over_a_higher_held_pin
    doc = Automation::CiVarsWriter.files(repos, { MISC => 'v0.0.37' }, 'MISC_REF' => 'v0.0.44')
                                  .fetch('live/producers/generated.auto.tfvars')

    assert_match(/^MISC_REF\s+= "v0\.0\.37"$/, doc)
  end

  def test_module_prefixed_versions_compare_on_their_semver
    assert_match(%r{^GO_MODULES_CHE_REF\s+= "che/v0\.0\.109"$}, current('GO_MODULES_CHE_REF' => 'che/v0.0.109'))
  end

  def test_parse_tfvars_reads_the_held_pins
    held = Automation::CiVarsWriter.parse_tfvars(current('MISC_REF' => 'v0.0.44'))

    assert_equal 'v0.0.44', held['MISC_REF']
  end

  #[why] consumers record what they resolved at build time, so a producer release must not rewrite
  #   them: that pin moves only when the consumer merges the bump
  def test_a_release_leaves_consumer_pins_untouched
    consumer = Automation::CiVarsWriter.files(repos, MISC => 'v0.0.37')
                                       .fetch('live/consumers/go-modules/generated.auto.tfvars')

    assert_includes consumer, 'MISC_REF = "v0.0.30"'
  end
end
##[<] 🤖🤖
