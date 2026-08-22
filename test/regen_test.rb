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

  def test_stale_mr_is_literal_same_scope_and_never_a_major_bump
    p = plan('PROSE_ASSETS_REF', 'v0.0.45', { 'a.tfvars' => %(PROSE_ASSETS_REF = "v0.0.44"\n) })
    assert p.stale_mr?('[automation] chore(prose-assets): v0.0.43 → v0.0.44')
    refute p.stale_mr?('[automation] chore(prose-assets): v0.0.43 → v1.0.0')
    refute p.stale_mr?('[automation] chore(prose-spec): v0.0.9 → v0.0.10')
    refute p.stale_mr?('Xautomation. chore(prose-assets): fake')
  end
end

class BotIdentityTest < Minitest::Test
  def identity_of(user) = Automation::RegenRunner.git_identity_of(user)

  def test_a_real_bot_user_becomes_a_noreply_author
    assert_equal ['cross-repo-bot', '42-cross-repo-bot@noreply.gitlab.com'],
                 identity_of({ 'username' => 'cross-repo-bot', 'id' => 42 })
  end

  def test_an_empty_username_resolves_to_no_author
    assert_nil identity_of({ 'username' => '', 'id' => 42 })
  end

  def test_a_zero_id_resolves_to_no_author
    assert_nil identity_of({ 'username' => 'cross-repo-bot', 'id' => 0 })
  end

  def test_a_response_missing_either_field_resolves_to_no_author
    assert_nil identity_of({ 'id' => 42 })
    assert_nil identity_of({ 'username' => 'cross-repo-bot' })
    assert_nil identity_of({})
  end

  def test_a_missing_response_resolves_to_no_author
    assert_nil identity_of(nil)
  end
end
##[<] 🤖🤖
