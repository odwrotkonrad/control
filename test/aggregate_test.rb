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

  def test_retry_recovers_from_transient_errors_with_backoff
    pauses = []
    calls = 0
    res = nil
    capture_io do
      res = Automation::Aggregate.with_retry('GET /x', attempts: 4, pause: 1, sleeper: ->(s) { pauses << s }) do
        calls += 1
        raise Net::OpenTimeout, 'boom' if calls < 3

        Net::HTTPOK.new('1.1', '200', 'OK')
      end
    end
    assert_equal 3, calls
    assert_equal [1, 2], pauses
    assert_instance_of Net::HTTPOK, res
  end

  def test_retry_treats_5xx_as_transient_and_gives_up
    calls = 0
    err = assert_raises(RuntimeError) do
      capture_io do
        Automation::Aggregate.with_retry('GET /x', attempts: 3, pause: 0, sleeper: ->(_) {}) do
          calls += 1
          Net::HTTPBadGateway.new('1.1', '502', 'Bad Gateway')
        end
      end
    end
    assert_equal 3, calls
    assert_match(/gave up after 3 attempts, last failure: status 502/, err.message)
  end

  def test_retry_returns_non_transient_responses_at_once
    calls = 0
    res = Automation::Aggregate.with_retry('GET /x', attempts: 3, pause: 0, sleeper: ->(_) { flunk 'slept' }) do
      calls += 1
      Net::HTTPNotFound.new('1.1', '404', 'Not Found')
    end
    assert_equal 1, calls
    assert_instance_of Net::HTTPNotFound, res
  end

  def test_retry_propagates_non_transient_errors
    assert_raises(ArgumentError) do
      Automation::Aggregate.with_retry('GET /x', attempts: 3, pause: 0, sleeper: ->(_) { flunk 'slept' }) { raise ArgumentError }
    end
  end
end
##[<] 🤖🤖
