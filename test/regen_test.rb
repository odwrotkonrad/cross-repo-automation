##[>] 🤖🤖
require 'minitest/autorun'
require 'automation'

class RegenTest < Minitest::Test
  def plan(key, tag, files, prev: nil)
    Automation::Regen.plan(repo: 'cross-repo/infra/iac', key: key, tag: tag, prev: prev, files: files)
  end

  def test_patch_bump_keeps_the_pin_format_and_auto_merges
    p = plan('PROSE_ASSETS_REF', 'v0.0.45', { 'tf/terraform.tfvars' => %(PROSE_ASSETS_REF = "v0.0.44"\n) })
    assert_equal ['tf/terraform.tfvars'], p.pin_files
    assert_equal %w[v0.0.44 v0.0.45 patch], [p.old, p.shown_tag, p.bump]
    assert_equal 'prose-assets-v0.0.45', p.branch
    assert_equal '[automation] chore(prose-assets): v0.0.44 → v0.0.45', p.title
    assert_equal 'Automated prose-assets regen: v0.0.44 → v0.0.45 (patch bump).', p.body
    assert p.auto_merge?
    assert_equal({ 'PROSE_ASSETS_REF' => 'v0.0.45' }, p.render_env)
  end

  def test_bare_pin_compares_spells_and_writes_without_v
    p = plan('CHE_PACKAGES_REF', 'v0.1.0', { 'tf/terraform.tfvars' => %(CHE_PACKAGES_REF = "0.0.16"\n) })
    assert_equal %w[0.0.16 0.1.0 minor], [p.old, p.shown_tag, p.bump]
    assert_equal '[automation] chore(che-packages): 0.0.16 → 0.1.0', p.title
    assert_equal '0.1.0', p.pin_written
  end

  def test_major_bump_waits_for_a_human
    p = plan('CI_IMAGES_REF', 'v1.0.0', { 'tf/terraform.tfvars' => %(CI_IMAGES_REF = "v0.0.101"\n) })
    assert_equal 'major', p.bump
    refute p.auto_merge?
  end

  def test_non_semver_seed_is_a_major_bump_spelled_as_the_tag
    p = plan('CI_IMAGES_REF', 'v0.0.5', { 'tf/terraform.tfvars' => %(CI_IMAGES_REF = "latest"\n) })
    assert_equal %w[latest v0.0.5 major], [p.old, p.shown_tag, p.bump]
    assert_equal 'v0.0.5', p.pin_written
  end

  def test_already_pinned_skips_across_formats
    skip = plan('CHE_PACKAGES_REF', 'v0.0.16', { 'tf/terraform.tfvars' => %(CHE_PACKAGES_REF = "0.0.16"\n) })
    assert_instance_of Automation::Regen::Skip, skip
    assert_equal 'cross-repo/infra/iac: already pinned to 0.0.16', skip.message
  end

  def test_no_pin_file_is_a_content_regen_rendered_at_the_key
    p = plan('PROSE_ASSETS_REF', 'v0.0.45', { 'x.tfvars' => 'nothing here' }, prev: 'v0.0.44')
    assert p.content_only
    assert_equal %w[v0.0.44 v0.0.45 patch], [p.old, p.shown_tag, p.bump]
    assert_equal 'docs-gen-prose-assets-v0.0.45', p.branch
    assert_equal '[automation] chore(docs-gen): render at prose-assets v0.0.45', p.title
    assert_equal 'Automated docs regen: rendered at prose-assets v0.0.45.', p.body
    assert_equal({ 'PROSE_ASSETS_REF' => 'v0.0.45' }, p.render_env)
    assert_equal 'none', plan('PROSE_ASSETS_REF', 'v0.0.45', {}).old
  end

  def test_rewrite_pin_moves_every_occurrence_in_the_files_format
    content = %(CHE_PACKAGES_REF = "0.0.16"\nother = "v1.2.3"\nCHE_PACKAGES_REF="latest"\n)
    p = plan('CHE_PACKAGES_REF', 'v0.0.17', { 'a.tfvars' => content })
    assert_equal %(CHE_PACKAGES_REF = "0.0.17"\nother = "v1.2.3"\nCHE_PACKAGES_REF="0.0.17"\n), Automation::Regen.rewrite_pin(content, p)
    v = plan('PROSE_ASSETS_REF', 'v0.0.45', { 'a.tfvars' => %(PROSE_ASSETS_REF = "v0.0.44"\n) })
    assert_equal %(PROSE_ASSETS_REF = "v0.0.45"\n), Automation::Regen.rewrite_pin(%(PROSE_ASSETS_REF = "v0.0.44"\n), v)
  end

  #[why] the lockfile is what makes a consumer regen a real pin bump: without it every consumer
  #   planned content_only and opened no MR at all, so a release never reached it
  def test_a_lockfile_pin_plans_a_real_bump_not_a_content_regen
    p = plan('MISC_REF', 'v0.0.38', { '.repo/upstream.env' => %(PROSE_ASSETS_REF=v0.0.63\nMISC_REF=v0.0.37\n) })
    refute p.content_only
    assert_equal ['.repo/upstream.env'], p.pin_files
    assert_equal %w[v0.0.37 v0.0.38 patch], [p.old, p.shown_tag, p.bump]
    assert_equal '[automation] chore(misc): v0.0.37 → v0.0.38', p.title
    assert p.auto_merge?
  end

  def test_a_lockfile_pin_rewrites_only_its_own_key_unquoted
    content = %(PROSE_ASSETS_REF=v0.0.63\nMISC_REF=v0.0.37\n)
    p = plan('MISC_REF', 'v0.0.38', { '.repo/upstream.env' => content })
    assert_equal %(PROSE_ASSETS_REF=v0.0.63\nMISC_REF=v0.0.38\n),
                 Automation::Regen.rewrite_pin(content, p, '.repo/upstream.env')
  end

  def test_a_lockfile_already_at_the_tag_skips_instead_of_opening_an_empty_mr
    skip = plan('MISC_REF', 'v0.0.37', { '.repo/upstream.env' => %(MISC_REF=v0.0.37\n) })
    assert_instance_of Automation::Regen::Skip, skip
    assert_equal 'cross-repo/infra/iac: already pinned to v0.0.37', skip.message
  end

  #[why] a key named in the lockfile must not be matched by the tfvars pattern, or a repo holding
  #   both files would read its pin off the wrong one
  def test_a_lockfile_key_is_not_matched_in_a_tfvars_file
    p = plan('MISC_REF', 'v0.0.38', { 'tf/terraform.tfvars' => %(MISC_REF=v0.0.37\n) }, prev: 'v0.0.37')
    assert p.content_only
  end

  def test_stale_mr_is_literal_same_scope_and_never_a_major_bump
    p = plan('PROSE_ASSETS_REF', 'v0.0.45', { 'a.tfvars' => %(PROSE_ASSETS_REF = "v0.0.44"\n) })
    assert p.stale_mr?('[automation] chore(prose-assets): v0.0.43 → v0.0.44')
    refute p.stale_mr?('[automation] chore(prose-assets): v0.0.43 → v1.0.0')
    refute p.stale_mr?('[automation] chore(prose-spec): v0.0.9 → v0.0.10')
    refute p.stale_mr?('Xautomation. chore(prose-assets): fake')
  end

  def test_comment_body_mentions_the_reviewer_and_says_auto_merge_is_armed
    p = plan('PROSE_ASSETS_REF', 'v0.0.45', { 'tf/terraform.tfvars' => %(PROSE_ASSETS_REF = "v0.0.44"\n) })
    assert_equal '@konradodwrot Automated prose-assets regen: v0.0.44 → v0.0.45 (patch bump). Auto-merge armed.',
                 p.comment_body('konradodwrot')
  end

  def test_comment_body_says_a_major_bump_is_withheld
    p = plan('CI_IMAGES_REF', 'v1.0.0', { 'tf/terraform.tfvars' => %(CI_IMAGES_REF = "v0.0.101"\n) })
    assert_equal '@reviewbot Automated ci-images regen: v0.0.101 → v1.0.0 (major bump). Auto-merge withheld, awaiting review.',
                 p.comment_body('reviewbot')
  end

  def test_comment_body_of_a_content_regen_reads_as_a_docs_render
    p = plan('PROSE_ASSETS_REF', 'v0.0.45', { 'x.tfvars' => 'nothing here' }, prev: 'v0.0.44')
    assert_equal '@konradodwrot Automated docs regen: rendered at prose-assets v0.0.45. Auto-merge armed.',
                 p.comment_body('konradodwrot')
  end
end

class SubstantiveDiffTest < Minitest::Test
  def substantive?(diff) = Automation::Regen.substantive_diff?(diff)

  def test_a_tfvars_pin_bump_is_only_a_version_move
    refute substantive?(<<~DIFF)
      diff --git a/tf/terraform.tfvars b/tf/terraform.tfvars
      --- a/tf/terraform.tfvars
      +++ b/tf/terraform.tfvars
      @@ -7 +7 @@
      -MISC_REF = "v0.0.17"
      +MISC_REF = "v0.0.18"
    DIFF
  end

  def test_a_rendered_header_bump_is_only_a_version_move
    refute substantive?(<<~DIFF)
      diff --git a/README.md b/README.md
      --- a/README.md
      +++ b/README.md
      @@ -1 +1 @@
      -<!-- autogenerated using @gitlab.com/ko/prose/assets//repos/configs/templates/README.md.ontoRepo.tpl?ref=v0.0.54 -->
      +<!-- autogenerated using @gitlab.com/ko/prose/assets//repos/configs/templates/README.md.ontoRepo.tpl?ref=v0.0.55 -->
    DIFF
  end

  def test_a_reworded_sentence_beside_a_header_bump_is_content
    assert substantive?(<<~DIFF)
      diff --git a/README.md b/README.md
      --- a/README.md
      +++ b/README.md
      @@ -1 +1 @@
      -<!-- autogenerated using @gitlab.com/ko/prose/assets//repos/configs/templates/README.md.ontoRepo.tpl?ref=v0.0.51 -->
      +<!-- autogenerated using @gitlab.com/ko/prose/assets//repos/configs/templates/README.md.ontoRepo.tpl?ref=v0.0.52 -->
      @@ -12 +12 @@ Git-tracked dotfiles extended into root OS space.
      -Records a system's stateful configuration, not for frequent software updates.
      +Records a system's stateful configuration, not for churn.
    DIFF
  end

  def test_an_added_line_with_no_deleted_counterpart_is_content
    assert substantive?(<<~DIFF)
      diff --git a/README.md b/README.md
      --- a/README.md
      +++ b/README.md
      @@ -18,0 +19 @@ Records a system's stateful configuration, not for churn.
      +- Sole consumer of `cross-repo/prose/spec`: the conventions summary loads once.
    DIFF
  end

  def test_a_reworded_line_that_also_names_a_version_stays_content
    assert substantive?(<<~DIFF)
      diff --git a/docs/spec.md b/docs/spec.md
      --- a/docs/spec.md
      +++ b/docs/spec.md
      @@ -3 +3 @@
      -Pinned at v0.0.17, rendered by the watcher.
      +Pinned at v0.0.18, rendered by the pipeline.
    DIFF
  end

  def test_an_empty_diff_is_not_content
    refute substantive?('')
  end
end

class BotIdentityTest < Minitest::Test
  def identity_of(user) = Automation::RegenRunner.git_identity_of(user)

  def test_a_real_bot_user_becomes_a_noreply_author
    assert_equal ['ko-automation', '42-ko-automation@noreply.gitlab.com'],
                 identity_of({ 'username' => 'ko-automation', 'id' => 42 })
  end

  def test_an_empty_username_resolves_to_no_author
    assert_nil identity_of({ 'username' => '', 'id' => 42 })
  end

  def test_a_zero_id_resolves_to_no_author
    assert_nil identity_of({ 'username' => 'ko-automation', 'id' => 0 })
  end

  def test_a_matched_username_resolves_to_its_id
    assert_equal 7, Automation::RegenRunner.user_id_of([{ 'id' => 7, 'username' => 'konradodwrot' }])
  end

  def test_an_unmatched_username_resolves_to_no_id
    assert_nil Automation::RegenRunner.user_id_of([])
    assert_nil Automation::RegenRunner.user_id_of(nil)
    assert_nil Automation::RegenRunner.user_id_of([{ 'username' => 'ghost' }])
  end

  def test_a_response_missing_either_field_resolves_to_no_author
    assert_nil identity_of({ 'id' => 42 })
    assert_nil identity_of({ 'username' => 'ko-automation' })
    assert_nil identity_of({})
  end

  def test_a_missing_response_resolves_to_no_author
    assert_nil identity_of(nil)
  end
end
##[<] 🤖🤖
