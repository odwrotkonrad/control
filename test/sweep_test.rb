##[>] 🤖🤖
require 'minitest/autorun'
require 'automation'

class SweepTest < Minitest::Test
  def mr(title: '[automation] chore(prose-assets): v0.0.44 → v0.0.45', armed: false, status: 'running', merge_status: 'mergeable')
    { 'title' => title, 'merge_when_pipeline_succeeds' => armed, 'head_pipeline' => status && { 'status' => status }, 'detailed_merge_status' => merge_status }
  end

  def decide(**kw)
    Automation::Sweep.decide(mr(**kw))
  end

  def test_ignores_human_mrs
    assert_equal :ignore, decide(title: 'feat: something').action
  end

  def test_skips_major_bumps
    assert_equal [:skip, 'major bump, human review'], decide(title: '[automation] chore(misc): v0.0.5 → v1.0.0').to_a
  end

  def test_armed_is_ok
    assert_equal :ok, decide(armed: true).action
  end

  def test_green_merges
    assert_equal [:merge, 'merge (pipeline green)'], decide(status: 'success').to_a
  end

  def test_running_arms
    assert_equal [:arm, 'arm auto-merge (pipeline pending)'], decide(status: 'pending').to_a
  end

  def test_red_and_unknown_are_left
    assert_equal [:leave, 'pipeline failed, needs a human'], decide(status: 'failed').to_a
    assert_equal [:leave, 'pipeline none, merge status mergeable'], decide(status: nil).to_a
  end
end
##[<] 🤖🤖
