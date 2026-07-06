defmodule ExNtfy.TestHelpers do
  @moduledoc """
  Shared helpers for ExNtfy tests.
  """

  @doc """
  Wires a `Req.Test` stub for the calling test and returns client options
  that route SDK HTTP calls through it, e.g. `ExNtfy.Client.new(req_stub(fun))`.
  """
  @spec req_stub((Plug.Conn.t() -> Plug.Conn.t())) :: keyword()
  def req_stub(fun) when is_function(fun, 1) do
    Req.Test.stub(ExNtfy, fun)
    [req_options: [plug: {Req.Test, ExNtfy}]]
  end

  @doc """
  Splits a binary into random-sized chunks (1–7 bytes) using a fixed seed, for
  property-style parser tests: any chunking must yield identical events.
  """
  @spec chunks_of(binary(), integer()) :: [binary()]
  def chunks_of(binary, seed) do
    :rand.seed(:exsss, {seed, 17, 29})
    split_random(binary, [])
  end

  defp split_random(<<>>, acc), do: Enum.reverse(acc)

  defp split_random(binary, acc) do
    size = min(byte_size(binary), :rand.uniform(7))
    <<chunk::binary-size(^size), rest::binary>> = binary
    split_random(rest, [chunk | acc])
  end

  @doc """
  Feeds chunks through a stream parser (`new/0` + `feed/2`), returning all
  emitted messages in order.
  """
  @spec feed_all(module(), [binary()]) :: [ExNtfy.Message.t()]
  def feed_all(parser_mod, chunks) do
    {messages, _state} =
      Enum.reduce(chunks, {[], parser_mod.new()}, fn chunk, {acc, state} ->
        {messages, state} = parser_mod.feed(state, chunk)
        {acc ++ messages, state}
      end)

    messages
  end
end
