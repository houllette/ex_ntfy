defmodule ExNtfy.Stream.SSETest do
  use ExUnit.Case, async: true

  import ExNtfy.TestHelpers

  alias ExNtfy.{Fixtures, Message}
  alias ExNtfy.Stream.SSE

  defp fixture_stream do
    """
    event: open
    data: #{JSON.encode!(Fixtures.open_map())}

    data: #{JSON.encode!(Fixtures.full_message_map())}

    : this is a comment

    event: keepalive
    data: #{JSON.encode!(Fixtures.keepalive_map())}

    """
  end

  test "parses data payloads, ignoring event fields and comments" do
    assert [
             %Message{event: :open},
             %Message{event: :message, id: "sPs71M8A2T"},
             %Message{event: :keepalive}
           ] = feed_all(SSE, [fixture_stream()])
  end

  test "any chunking of the stream yields identical events" do
    stream = fixture_stream()
    expected = feed_all(SSE, [stream])
    assert length(expected) == 3

    for seed <- 1..25 do
      assert feed_all(SSE, chunks_of(stream, seed)) == expected,
             "chunking with seed #{seed} diverged"
    end
  end

  test "joins multi-line data fields with a newline before parsing" do
    # Split at a JSON token boundary: the SSE-mandated \n join is valid
    # whitespace there, so the event parses iff the join happened.
    stream =
      ~s(data: {"id": "F2ZoyEBBg9", "time": 1735920011,\n) <>
        ~s(data: "event": "keepalive", "topic": "mytopic"}\n\n)

    assert [%Message{event: :keepalive, id: "F2ZoyEBBg9"}] = feed_all(SSE, [stream])
  end

  test "tolerates CRLF line endings" do
    stream = "event: keepalive\r\ndata: #{JSON.encode!(Fixtures.keepalive_map())}\r\n\r\n"
    assert [%Message{event: :keepalive}] = feed_all(SSE, [stream])
  end

  test "data without the space after the colon still parses" do
    stream = "data:#{JSON.encode!(Fixtures.keepalive_map())}\n\n"
    assert [%Message{event: :keepalive}] = feed_all(SSE, [stream])
  end

  test "a blank line without accumulated data emits nothing" do
    assert [] = feed_all(SSE, ["\n\n\n"])
  end

  test "an event is only dispatched on the blank line" do
    {messages, state} = SSE.feed(SSE.new(), "data: #{JSON.encode!(Fixtures.keepalive_map())}\n")
    assert messages == []

    {messages, _state} = SSE.feed(state, "\n")
    assert [%Message{event: :keepalive}] = messages
  end

  test "drops malformed data payloads" do
    stream = "data: not json {\n\ndata: #{JSON.encode!(Fixtures.open_map())}\n\n"
    assert [%Message{event: :open}] = feed_all(SSE, [stream])
  end
end
