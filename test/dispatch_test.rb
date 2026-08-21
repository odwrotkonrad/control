##[>] 🤖🤖
require 'minitest/autorun'
require 'automation'

class DispatchTest < Minitest::Test
  FIXTURE = File.expand_path('fixture', __dir__)

  def setup
    @graph = Automation::Graph.load("#{FIXTURE}/graph.yml")
  end

  def dispatch(name, producers: Automation::PRODUCERS)
    event = Automation::Event.parse(File.read("#{FIXTURE}/#{name}.json"))
    Automation.dispatch(event, graph: @graph, producers: producers)
  end

  def test_release_published_pins_iac_only
    assert_equal File.read("#{FIXTURE}/release-published.yml"), dispatch('release-published')
  end

  def test_release_published_without_group_var_regenerates_consumers
    producers = { 'prose-assets' => Automation::Producer.new(name: 'prose-assets', var_key: nil, artifact: 'cross-repo/prose/assets') }
    yaml = dispatch('release-published', producers: producers)
    assert_equal %w[ai-sandbox configs cross-repo/automation cross-repo/infra/iac], yaml.scan(/^regen:(\S+):$/).flatten
  end

  def test_release_published_unknown_producer_raises
    json = File.read("#{FIXTURE}/release-published.json").sub('prose-assets', 'nobody')
    event = Automation::Event.parse(json)
    assert_raises(ArgumentError) { Automation.dispatch(event, graph: @graph) }
  end

  def test_ci_var_changed_regenerates_consumers_at_the_new_value_and_skips_iac_and_unknown_keys
    assert_equal File.read("#{FIXTURE}/ci-var-changed.yml"), dispatch('ci-var-changed')
  end

  def test_ci_var_changed_empty_is_a_noop_job
    assert_equal File.read("#{FIXTURE}/ci-var-changed-empty.yml"), dispatch('ci-var-changed-empty')
  end

  def test_every_job_runs_small
    %w[release-published ci-var-changed ci-var-changed-empty].each do |name|
      yaml = dispatch(name)
      assert_equal yaml.scan(/^  tags:$/).size, yaml.scan(/^    - gke-linux-amd64-small$/).size, name
    end
  end

  def test_unknown_type_has_no_handler
    event = Automation::Event.new(type: 'thing.happened', source: {}, details: {})
    assert_raises(KeyError) { Automation.dispatch(event, graph: @graph) }
  end
end
##[<] 🤖🤖
