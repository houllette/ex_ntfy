defmodule ExNtfy.Stream.NDJSONTest do
  use ExUnit.Case, async: true

  import ExNtfy.TestHelpers

  alias ExNtfy.{Fixtures, Message}
  alias ExNtfy.Stream.NDJSON

  defp fixture_stream do
    [
      Fixtures.open_map(),
      Fixtures.full_message_map(),
      Fixtures.keepalive_map(),
      Fixtures.clear_response_map()
    ]
    |> Enum.map_join("", &(JSON.encode!(&1) <> "\n"))
  end

  test "parses a whole ndjson stream into all events in order" do
    assert [
             %Message{event: :open},
             %Message{event: :message, id: "sPs71M8A2T"},
             %Message{event: :keepalive},
             %Message{event: :message_clear, sequence_id: "xE73Iyuabi"}
           ] = feed_all(NDJSON, [fixture_stream()])
  end

  test "buffers a partial trailing line until its newline arrives" do
    line = JSON.encode!(Fixtures.keepalive_map()) <> "\n"
    {first, second} = String.split_at(line, 12)

    {messages, state} = NDJSON.feed(NDJSON.new(), first)
    assert messages == []

    {messages, _state} = NDJSON.feed(state, second)
    assert [%Message{event: :keepalive}] = messages
  end

  test "any chunking of the stream yields identical events" do
    stream = fixture_stream()
    expected = feed_all(NDJSON, [stream])
    assert length(expected) == 4

    for seed <- 1..25 do
      assert feed_all(NDJSON, chunks_of(stream, seed)) == expected,
             "chunking with seed #{seed} diverged"
    end
  end

  test "tolerates CRLF line endings" do
    stream = JSON.encode!(Fixtures.keepalive_map()) <> "\r\n"
    assert [%Message{event: :keepalive}] = feed_all(NDJSON, [stream])
  end

  test "drops malformed lines, keeping the rest" do
    stream =
      JSON.encode!(Fixtures.keepalive_map()) <>
        "\nnot json {\n" <> JSON.encode!(Fixtures.open_map()) <> "\n"

    assert [%Message{event: :keepalive}, %Message{event: :open}] = feed_all(NDJSON, [stream])
  end

  test "skips blank lines" do
    stream = "\n\n" <> JSON.encode!(Fixtures.keepalive_map()) <> "\n\n"
    assert [%Message{event: :keepalive}] = feed_all(NDJSON, [stream])
  end
end
