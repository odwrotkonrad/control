##[>] 🤖🤖
require 'minitest/autorun'
require 'automation'

class AggregateTest < Minitest::Test
  SEEDS = {
    'configs' => { 'upstream' => ['go-modules/che'], 'downstream' => [{ 'name' => 'llm/claude', 'type' => 'ai-prose' }] },
    'go-modules' => { 'edges' => { 'go-modules/lib' => ['che'] }, 'downstream' => [{ 'name' => 'che', 'type' => 'binary' }, { 'name' => 'lib', 'type' => 'go-module' }] }
  }.freeze

  def test_declaration_overrides_its_seed
    declared = { 'configs' => { 'upstream' => ['go-modules/lib'], 'downstream' => [] } }
    assert_equal ['go-modules/lib'], Automation::Aggregate.combine(SEEDS, declared)['configs']['upstream']
  end

  def test_consistent_interfaces_report_nothing
    assert_equal [], Automation::Aggregate.inconsistencies(SEEDS)
  end

  def test_missing_producer_and_bad_edge_are_named_once
    repos = SEEDS.merge('notes' => { 'upstream' => ['nobody/thing', 'nobody/thing'], 'edges' => { 'go-modules/che' => ['ghost'] } })
    assert_equal ['notes edge into ghost, which notes does not produce', 'notes consumes nobody/thing, which no repo produces'],
                 Automation::Aggregate.inconsistencies(repos)
  end

  def test_render_matches_the_committed_graph_format
    expected = <<~YAML
      ##[>] 🤖
      repositories:
        - repo: configs
          artifacts:
            - {name: llm/claude, type: ai-prose}
        - repo: go-modules
          artifacts:
            - {name: che, type: binary}
            - {name: lib, type: go-module}
        - repo: notes
          artifacts: []
      edges:
        go-modules/che:
          - configs
        go-modules/lib:
          - go-modules/che
      ##[<] 🤖
    YAML
    assert_equal expected, Automation::Aggregate.render(SEEDS.merge('notes' => {}))
  end
end
##[<] 🤖🤖
