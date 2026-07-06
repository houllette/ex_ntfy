defmodule ExNtfy.Subscribe.Options do
  # The schema is defined as a plain variable so its generated docs can be
  # interpolated into @moduledoc below.
  schema_def = [
    since: [
      type: {:custom, __MODULE__, :validate_since, []},
      doc:
        "Return cached messages since: a duration or message-ID string (passed " <>
          "through verbatim — the server disambiguates), a non-negative unix " <>
          "timestamp, a `DateTime`, `:all`, or `:latest` (most recent message only)."
    ],
    scheduled: [
      type: :boolean,
      doc: "`true` includes not-yet-delivered scheduled messages."
    ],
    id: [type: :string, doc: "Filter: exact message ID."],
    message: [type: :string, doc: "Filter: exact message body match."],
    title: [type: :string, doc: "Filter: exact title match."],
    priority: [
      type: {:custom, __MODULE__, :validate_priority, []},
      doc:
        "Filter: a single priority or a list (**any** match / logical OR) — " <>
          "`1..5` or the same atoms as publishing (`:min` … `:urgent`)."
    ],
    tags: [
      type: {:list, {:or, [:string, :atom]}},
      doc: "Filter: list of tags that must **all** match (logical AND)."
    ]
  ]

  @moduledoc """
  Validates subscribe options and builds subscribe URLs — shared
  infrastructure for one-shot polling (`ExNtfy.poll/2`, Phase 5) and the
  Phase 6 streaming subscriptions, which call `path/2` with a stream format
  and `to_query/1` without `poll=1`.

  `path/2` builds the topic path (single topic, list, or comma-separated
  string — topics are individually percent-escaped); `to_query/1` validates
  and encodes the options below, raising `NimbleOptions.ValidationError` on
  anything unknown.

  ## Options

  #{NimbleOptions.docs(schema_def)}
  """

  alias ExNtfy.Publish

  @schema NimbleOptions.new!(schema_def)

  @query_order [:since, :scheduled, :id, :message, :title, :priority, :tags]

  @formats [:json, :sse, :raw, :ws]

  @typedoc "One or many topic names."
  @type topics :: String.t() | [String.t()]

  @typedoc "Any subscribe option from the schema above."
  @type option :: {atom(), term()}

  @doc """
  Builds the subscribe path for one or many topics and a stream format.

  Topics may be a string, a list, or a comma-separated string; each topic is
  percent-escaped individually (commas stay as separators).

  ## Examples

      iex> ExNtfy.Subscribe.Options.path("mytopic")
      "/mytopic/json"

      iex> ExNtfy.Subscribe.Options.path(["topic1", "topic2"], :sse)
      "/topic1,topic2/sse"

  """
  @spec path(topics(), :json | :sse | :raw | :ws) :: String.t()
  def path(topics, format \\ :json) when format in @formats do
    "/" <> topics_segment(topics) <> "/" <> Atom.to_string(format)
  end

  @doc """
  Joins and percent-escapes topics into a single path segment.

  ## Examples

      iex> ExNtfy.Subscribe.Options.topics_segment(["alerts", "backups"])
      "alerts,backups"

  """
  @spec topics_segment(topics()) :: String.t()
  def topics_segment(topics) do
    case topics |> List.wrap() |> Enum.flat_map(&String.split(&1, ",", trim: true)) do
      [] ->
        raise ArgumentError, "expected at least one topic, got: #{inspect(topics)}"

      segments ->
        Enum.map_join(segments, ",", fn segment ->
          URI.encode(segment, &URI.char_unreserved?/1)
        end)
    end
  end

  @doc """
  Validates subscribe options and encodes them as query parameters, in a
  stable canonical order. `poll=1` is not an option — `ExNtfy.poll/2` adds it
  itself.

  ## Examples

      iex> ExNtfy.Subscribe.Options.to_query(since: :latest, scheduled: true)
      [since: "latest", scheduled: "1"]

      iex> ExNtfy.Subscribe.Options.to_query(priority: [:high, 5], tags: [:warning, "backup"])
      [priority: "4,5", tags: "warning,backup"]

  """
  @spec to_query([option()]) :: keyword(String.t())
  def to_query(opts) do
    opts = NimbleOptions.validate!(opts, @schema)

    for key <- @query_order,
        {:ok, raw} <- [Keyword.fetch(opts, key)],
        value = encode(key, raw),
        do: {key, value}
  end

  defp encode(:since, %DateTime{} = dt), do: dt |> DateTime.to_unix() |> Integer.to_string()
  defp encode(:since, int) when is_integer(int), do: Integer.to_string(int)
  defp encode(:since, atom) when atom in [:all, :latest], do: Atom.to_string(atom)
  defp encode(:since, string), do: string
  defp encode(:scheduled, true), do: "1"
  defp encode(:scheduled, false), do: nil

  defp encode(:priority, value) do
    value
    |> List.wrap()
    |> Enum.map_join(",", fn priority ->
      priority |> Publish.Options.priority_int() |> Integer.to_string()
    end)
  end

  defp encode(:tags, tags), do: Enum.map_join(tags, ",", &to_string/1)
  defp encode(_key, value), do: value

  @doc false
  @spec validate_since(term()) ::
          {:ok, String.t() | non_neg_integer() | DateTime.t() | :all | :latest}
          | {:error, String.t()}
  def validate_since(%DateTime{} = dt), do: {:ok, dt}
  def validate_since(int) when is_integer(int) and int >= 0, do: {:ok, int}
  def validate_since(atom) when atom in [:all, :latest], do: {:ok, atom}
  def validate_since(string) when is_binary(string), do: {:ok, string}

  def validate_since(other) do
    {:error,
     "expected a duration/message-id string, a non-negative unix timestamp, a DateTime, " <>
       ":all, or :latest, got: #{inspect(other)}"}
  end

  @doc false
  @spec validate_priority(term()) :: {:ok, term()} | {:error, String.t()}
  def validate_priority([]), do: {:error, "expected at least one priority, got an empty list"}

  def validate_priority(value) do
    value
    |> List.wrap()
    |> Enum.reduce_while({:ok, value}, fn priority, acc ->
      case Publish.Options.validate_priority(priority) do
        {:ok, _priority} -> {:cont, acc}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end
end
