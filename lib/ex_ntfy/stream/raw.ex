defmodule ExNtfy.Stream.Raw do
  @moduledoc """
  Incremental parser for ntfy's `/raw` stream: each line is a message *body*
  only, an empty line is a keepalive.

  Messages are synthesized with `event: :message` and the line as `message` —
  there is no metadata on this stream, so `id`/`time`/`topic` are `nil` and
  reconnects cannot resume with `since=<id>`. Prefer `/json` unless you truly
  only need bodies. Pure and stateful: `new/0` then `feed/2`.
  """

  alias ExNtfy.Message

  @typedoc "Parser state: the buffered partial line."
  @opaque t :: binary()

  @doc "Returns a fresh parser state."
  @spec new() :: t()
  def new, do: ""

  @doc """
  Feeds a chunk, returning `{messages, state}`: one synthesized `:message`
  per body line, one `:keepalive` per empty line.
  """
  @spec feed(t(), binary()) :: {[Message.t()], t()}
  def feed(buffer, chunk) do
    parts = String.split(buffer <> chunk, "\n")
    {lines, [rest]} = Enum.split(parts, -1)
    messages = Enum.map(lines, &synthesize(String.trim_trailing(&1, "\r")))
    {messages, rest}
  end

  defp synthesize("") do
    %Message{id: nil, time: nil, event: :keepalive, topic: nil}
  end

  defp synthesize(line) do
    %Message{id: nil, time: nil, event: :message, topic: nil, message: line}
  end
end
