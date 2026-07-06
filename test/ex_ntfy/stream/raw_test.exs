defmodule ExNtfy.Stream.RawTest do
  use ExUnit.Case, async: true

  import ExNtfy.TestHelpers

  alias ExNtfy.Message
  alias ExNtfy.Stream.Raw

  test "each line becomes a synthesized message event with body only" do
    assert [first, second] = feed_all(Raw, ["backup done\ndisk almost full\n"])

    assert %Message{event: :message, message: "backup done", id: nil, time: nil, topic: nil} =
             first

    assert %Message{event: :message, message: "disk almost full"} = second
  end

  test "empty lines become keepalive events" do
    assert [%Message{event: :keepalive, message: nil}] = feed_all(Raw, ["\n"])
  end

  test "buffers partial lines across chunks" do
    {messages, state} = Raw.feed(Raw.new(), "backup ")
    assert messages == []

    {messages, _state} = Raw.feed(state, "done\n")
    assert [%Message{event: :message, message: "backup done"}] = messages
  end

  test "any chunking yields identical events" do
    stream = "one\n\ntwo\nthree\n\n"
    expected = feed_all(Raw, [stream])
    assert length(expected) == 5

    for seed <- 1..25 do
      assert feed_all(Raw, chunks_of(stream, seed)) == expected,
             "chunking with seed #{seed} diverged"
    end
  end

  test "tolerates CRLF line endings" do
    assert [%Message{event: :message, message: "hello"}] = feed_all(Raw, ["hello\r\n"])
  end
end
