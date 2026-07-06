defmodule ExNtfy.Stream.NDJSON do
  # Incremental parser for ntfy's /json stream (application/x-ndjson, one
  # JSON object per line). HTTP chunks are not line-aligned, so the parser
  # buffers a partial trailing line and emits messages only once their \n
  # arrives. Blank and unparsable lines are dropped. Pure and stateful:
  # new/0 then feed/2.
  @moduledoc false

  alias ExNtfy.Message

  @typedoc "Parser state: the buffered partial line."
  @opaque t :: binary()

  @doc "Returns a fresh parser state."
  @spec new() :: t()
  def new, do: ""

  @doc """
  Feeds a chunk, returning `{messages, state}` with every completed line
  parsed via `ExNtfy.Message.from_json/1`.
  """
  @spec feed(t(), binary()) :: {[Message.t()], t()}
  def feed(buffer, chunk) do
    parts = String.split(buffer <> chunk, "\n")
    {lines, [rest]} = Enum.split(parts, -1)
    messages = Enum.flat_map(lines, &parse_line/1)
    {messages, rest}
  end

  defp parse_line(line) do
    case line |> String.trim_trailing("\r") |> Message.from_json() do
      {:ok, message} -> [message]
      {:error, _reason} -> []
    end
  end
end
