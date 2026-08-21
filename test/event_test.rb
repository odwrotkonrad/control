##[>] 🤖🤖
require 'minitest/autorun'
require 'automation'

class EventTest < Minitest::Test
  FIXTURE = File.expand_path('fixture', __dir__)

  def test_parses_release_published
    event = Automation::Event.parse(File.read("#{FIXTURE}/release-published.json"))
    assert_equal 'release.published', event.type
    assert_equal 'konradodwrot/cross-repo/prose/assets', event.source['project']
    assert_equal 'v0.0.45', event.details['tag']
    assert_equal 'prose-assets v0.0.45', event.summary
  end

  def test_parses_ci_var_changed
    event = Automation::Event.parse(File.read("#{FIXTURE}/ci-var-changed.json"))
    assert_equal 'ci-var.changed', event.type
    assert_equal %w[GRP_KO_VAR_PROSE_ASSETS_REF GRP_KO_VAR_ARTIFACT_REGISTRY], event.details['variables'].map { |v| v['key'] }
  end

  def test_rejects_unknown_type
    err = assert_raises(ArgumentError) { Automation::Event.parse('{"type":"thing.happened","source":{},"details":{}}') }
    assert_match(/unknown event type "thing.happened"/, err.message)
  end

  def test_rejects_missing_fields
    json = '{"type":"release.published","source":{"project":"p"},"details":{"producer":"misc"}}'
    err = assert_raises(ArgumentError) { Automation::Event.parse(json) }
    assert_equal 'release.published event missing source.pipeline, source.ref, source.sha, details.artifact, details.tag', err.message
  end

  def test_rejects_no_type
    assert_raises(ArgumentError) { Automation::Event.parse('{"source":{},"details":{}}') }
  end
end
##[<] 🤖🤖
