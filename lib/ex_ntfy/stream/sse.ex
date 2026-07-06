defmodule ExNtfy.Stream.SSE do
  @moduledoc """
  Incremental parser for ntfy's `/sse` stream (EventSource format).

  Only `data:` fields carry the message JSON (the JSON's own `event` field
  governs — the SSE `event:` field is redundant and ignored, as are comments
  and other fields). Multi-line `data:` fields join with `\\n` per the SSE
  spec; a blank line dispatches the accumulated event. Pure and stateful:
  `new/0` then `feed/2`.
  """

  alias ExNtfy.Message

  @typedoc "Parser state: `{partial_line_buffer, accumulated_data_lines}`."
  @opaque t :: {binary(), [binary()]}

  @doc "Returns a fresh parser state."
  @spec new() :: t()
  def new, do: {"", []}

  @doc """
  Feeds a chunk, returning `{messages, state}` with one message per
  dispatched event whose joined `data:` payload parses via
  `ExNtfy.Message.from_json/1`.
  """
  @spec feed(t(), binary()) :: {[Message.t()], t()}
  def feed({buffer, data_acc}, chunk) do
    parts = String.split(buffer <> chunk, "\n")
    {lines, [rest]} = Enum.split(parts, -1)

    {messages, data_acc} =
      Enum.reduce(lines, {[], data_acc}, fn line, {messages, data_acc} ->
        case process_line(String.trim_trailing(line, "\r"), data_acc) do
          {:dispatch, data_acc} -> {messages ++ dispatch(data_acc), []}
          {:cont, data_acc} -> {messages, data_acc}
        end
      end)

    {messages, {rest, data_acc}}
  end

  defp process_line("", data_acc), do: {:dispatch, data_acc}
  defp process_line("data: " <> data, data_acc), do: {:cont, [data | data_acc]}
  defp process_line("data:" <> data, data_acc), do: {:cont, [data | data_acc]}
  # Comments (leading `:`) and other fields (`event:`, `id:`, `retry:`) are ignored.
  defp process_line(_line, data_acc), do: {:cont, data_acc}

  defp dispatch([]), do: []

  defp dispatch(data_acc) do
    payload = data_acc |> Enum.reverse() |> Enum.join("\n")

    case Message.from_json(payload) do
      {:ok, message} -> [message]
      {:error, _reason} -> []
    end
  end
end
