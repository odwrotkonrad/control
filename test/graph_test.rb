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

  def test_consumes_matches_repo_and_its_artifacts
    assert_equal %w[cross-repo/prose/assets/repo-prose go-modules/che], @graph.consumes('ai-sandbox')
    assert_equal %w[cross-repo/infra/oci-images/ci-linux go-modules/che], @graph.consumes('cross-repo/infra/oci-images')
  end
end
##[<] 🤖🤖
