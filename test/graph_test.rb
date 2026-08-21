##[>] 🤖🤖
require 'minitest/autorun'
require 'automation'

class GraphTest < Minitest::Test
  def setup
    @graph = Automation::Graph.load(File.expand_path('fixture/graph.yml', __dir__))
  end

  def test_affected_by_repo_covers_every_artifact_and_resolves_vertices_to_repos
    assert_equal %w[ai-sandbox configs cross-repo/automation cross-repo/infra/iac], @graph.affected('cross-repo/prose/assets')
  end

  def test_affected_by_artifact
    assert_equal %w[configs cross-repo/infra/iac], @graph.affected('cross-repo/prose/assets/license')
  end

  def test_affected_excludes_the_producing_repo
    assert_equal %w[configs cross-repo/infra/iac], @graph.affected('cross-repo/infra/oci-images/ci-linux')
  end

  def test_affected_unknown_vertex_is_empty
    assert_equal [], @graph.affected('nope')
  end

  def test_produces
    assert_equal %w[repo-prose license], @graph.produces('cross-repo/prose/assets')
    assert_equal [], @graph.produces('configs')
  end

  def test_pins_come_from_edges_into_ci_var_artifacts
    pins = @graph.pins
    assert_equal %w[cross-repo/infra/iac], pins.map(&:repo).uniq
    assert_equal %w[GRP_KO_VAR_CI_IMAGES_REF GRP_KO_VAR_PROSE_ASSETS_REF GRP_KO_VAR_PROSE_ASSETS_REF], pins.map(&:var_key).sort
    assert_equal %w[cross-repo/prose/assets/license cross-repo/prose/assets/repo-prose], @graph.pins_for_release('cross-repo/prose/assets').map(&:source).sort
    assert_equal %w[cross-repo/infra/oci-images/ci-linux], @graph.pins_for_release('cross-repo/infra/oci-images/ci-linux').map(&:source)
    assert_equal [], @graph.pins_for_release('go-modules/che')
    assert_equal %w[PROSE_ASSETS_REF], @graph.pins_for_var('GRP_KO_VAR_PROSE_ASSETS_REF').map(&:key).uniq
    assert_equal [], @graph.pins_for_var('GRP_KO_VAR_ARTIFACT_REGISTRY')
  end

  def test_pin_derivations
    assert_equal 'PROSE_ASSETS_REF', Automation::Pin.key_of('ci-var/prose-assets-ref')
    assert_equal 'prose-assets', Automation::Pin.label_of('PROSE_ASSETS_REF')
    assert_equal 'che-backup-auto-create', Automation::Pin.label_of('CHE_BACKUP_AUTO_CREATE')
  end

  def test_consumes_matches_repo_and_its_artifacts
    assert_equal %w[cross-repo/prose/assets/repo-prose go-modules/che], @graph.consumes('ai-sandbox')
    assert_equal %w[cross-repo/infra/oci-images/ci-linux go-modules/che], @graph.consumes('cross-repo/infra/oci-images')
  end
end
##[<] 🤖🤖
