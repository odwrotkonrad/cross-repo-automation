##[>] 🤖🤖
require 'minitest/autorun'
require 'automation'

class EventTest < Minitest::Test
  SOURCE = '{"project":"konradodwrot/notes","pipeline":"1","ref":"main","sha":"abc"}'.freeze

  def parse(json)
    Automation::Event.parse_all(json, catalogue: Automation::Events)
  end

  def test_parses_an_array_of_events_in_one_send
    json = "[{\"type\":\"artifacts.declared\",\"source\":#{SOURCE},\"details\":{\"repo\":\"notes\"}}," \
           "{\"type\":\"artifacts.consumed\",\"source\":#{SOURCE},\"details\":{\"repo\":\"notes\",\"consumes\":[]}}]"
    events = parse(json)
    assert_equal %w[artifacts.declared artifacts.consumed], events.map(&:type)
    assert_equal 'notes', events.first.repo
  end

  def test_a_bare_object_parses_as_an_array_of_one
    events = parse("{\"type\":\"artifacts.declared\",\"source\":#{SOURCE},\"details\":{\"repo\":\"notes\"}}")
    assert_equal 1, events.size
  end

  def test_legacy_type_names_resolve_through_their_alias
    json = "[{\"type\":\"release.published\",\"source\":#{SOURCE}," \
           '"details":{"artifact":"x","version":"v1"}}]'
    assert_equal 'artifact.released', parse(json).first.type
  end

  def test_rejects_unknown_type
    err = assert_raises(ArgumentError) { parse("[{\"type\":\"thing.happened\",\"source\":#{SOURCE},\"details\":{}}]") }
    assert_match(/unknown event type "thing.happened"/, err.message)
  end

  def test_rejects_missing_fields_naming_each_one
    err = assert_raises(ArgumentError) { parse('[{"type":"artifacts.consumed","source":{"project":"p"},"details":{}}]') }
    assert_equal 'artifacts.consumed event missing source.pipeline, source.ref, source.sha, details.repo, details.consumes',
                 err.message
  end

  def test_every_catalogue_entry_has_a_handler
    assert_equal Automation::Events.types.sort, Automation::HANDLERS.keys.sort
  end

  def test_every_alias_resolves_to_a_catalogue_entry
    Automation::Events::ALIASES.each_value { |target| assert_includes Automation::Events.types, target }
  end
end
##[<] 🤖🤖
