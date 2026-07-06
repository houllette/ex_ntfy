defmodule ExNtfy.Publish.Options do
  # The schema is defined as a plain variable so its generated docs can be
  # interpolated into @moduledoc below.
  schema_def = [
    message: [
      type: :string,
      doc:
        "Message body. On the JSON path this is normally the positional argument " <>
          "to `ExNtfy.publish/3`; as an option it matters for `ExNtfy.publish_raw/3` " <>
          "(e.g. an inline template) and `ExNtfy.trigger/2`."
    ],
    title: [type: :string, doc: "Notification title."],
    priority: [
      type: {:custom, __MODULE__, :validate_priority, []},
      doc: "`1..5` or `:min` | `:low` | `:default` | `:high` | `:max` | `:urgent`."
    ],
    tags: [
      type: {:list, {:or, [:string, :atom]}},
      doc: "Tags/emoji shortcodes; atoms and strings mix, order is preserved."
    ],
    markdown: [type: :boolean, doc: "Render the message body as Markdown."],
    delay: [
      type: {:custom, __MODULE__, :validate_delay, []},
      doc:
        "Scheduled delivery: a `DateTime`, a non-negative unix timestamp, or a " <>
          "string ntfy understands (`\"30m\"`, `\"tomorrow, 3pm\"`)."
    ],
    click: [type: :string, doc: "URL opened when the notification is tapped."],
    icon: [type: :string, doc: "JPEG/PNG URL used as the notification icon."],
    attach: [type: :string, doc: "Attach a file by URL."],
    filename: [type: :string, doc: "Attachment filename override."],
    actions: [
      type: {:custom, __MODULE__, :validate_actions, []},
      doc:
        "Up to 3 action buttons: `ExNtfy.Action` structs, ntfy-shaped maps, or a " <>
          "raw JSON string passed through untouched."
    ],
    email: [
      type: {:custom, __MODULE__, :validate_string_or_yes, []},
      doc: "Forward to an e-mail address, or `true` for the account's verified address."
    ],
    call: [
      type: {:custom, __MODULE__, :validate_string_or_yes, []},
      doc: "Phone call with the message read out: a number, or `true` for the verified one."
    ],
    sequence_id: [
      type: :string,
      doc: "Sequence ID for the update/clear/delete lifecycle."
    ],
    cache: [
      type: :boolean,
      doc: "`false` sends `X-Cache: no` (deliver only to live subscribers)."
    ],
    firebase: [
      type: :boolean,
      doc: "`false` sends `X-Firebase: no` (don't forward to FCM)."
    ],
    unified_push: [
      type: :boolean,
      doc: "`true` sends `X-UnifiedPush: 1`. Only for UnifiedPush apps."
    ],
    template: [
      type: {:custom, __MODULE__, :validate_template, []},
      doc:
        "`true` for inline templating, `:github` | `:grafana` | `:alertmanager` for " <>
          "pre-defined templates, or a custom server-side template name."
    ],
    poll_id: [
      type: :string,
      doc: "Internal (iOS instant notifications); pass-through only."
    ]
  ]

  @moduledoc """
  Validates publish options and encodes them for ntfy's three publish shapes:

    * `to_json_body/2` — the JSON publish (`POST /`, §1.3): most options become
      body fields; header-only options come back as headers for the same request.
    * `to_headers/1` — the raw-body publish (`POST /<topic>`, §1.2): every option
      becomes its canonical `X-` header, RFC 2047-encoding non-ASCII values.
    * `to_query/1` — the webhook-style publish (`GET /<topic>/trigger`): every
      option becomes a query parameter.

  All three validate first, so a mistyped option raises
  `NimbleOptions.ValidationError` instead of silently dropping a feature.

  ## Options

  #{NimbleOptions.docs(schema_def)}
  """

  alias ExNtfy.Action

  @schema NimbleOptions.new!(schema_def)

  @priority_atoms %{min: 1, low: 2, default: 3, high: 4, max: 5, urgent: 5}

  # Encoding order below follows the reference §1.2 table.
  @json_fields [
    message: "message",
    title: "title",
    priority: "priority",
    tags: "tags",
    delay: "delay",
    actions: "actions",
    click: "click",
    attach: "attach",
    markdown: "markdown",
    icon: "icon",
    filename: "filename",
    email: "email",
    call: "call",
    sequence_id: "sequence_id"
  ]

  @header_only [
    cache: "x-cache",
    firebase: "x-firebase",
    unified_push: "x-unifiedpush",
    template: "x-template",
    poll_id: "x-poll-id"
  ]

  @header_names [
                  message: "x-message",
                  title: "x-title",
                  priority: "x-priority",
                  tags: "x-tags",
                  delay: "x-delay",
                  actions: "x-actions",
                  click: "x-click",
                  attach: "x-attach",
                  markdown: "x-markdown",
                  icon: "x-icon",
                  filename: "x-filename",
                  email: "x-email",
                  call: "x-call",
                  sequence_id: "x-sequence-id"
                ] ++ @header_only

  @query_names [
    message: :message,
    title: :title,
    priority: :priority,
    tags: :tags,
    delay: :delay,
    actions: :actions,
    click: :click,
    attach: :attach,
    markdown: :markdown,
    icon: :icon,
    filename: :filename,
    email: :email,
    call: :call,
    sequence_id: :sid,
    cache: :cache,
    firebase: :firebase,
    unified_push: :up,
    template: :template,
    poll_id: :"poll-id"
  ]

  @typedoc "Any publish option from the schema above."
  @type option :: {atom(), term()}

  @doc """
  Encodes options for a JSON publish (`POST /`).

  Returns `{body, headers}`: the JSON body map (string keys, always including
  `"topic"`) plus the headers for the header-only options (`:cache`,
  `:firebase`, `:unified_push`, `:template`, `:poll_id`).

  ## Examples

      iex> ExNtfy.Publish.Options.to_json_body("alerts", message: "hi", priority: :high)
      {%{"topic" => "alerts", "message" => "hi", "priority" => 4}, []}

      iex> ExNtfy.Publish.Options.to_json_body("alerts", email: true, cache: false)
      {%{"topic" => "alerts", "email" => "yes"}, [{"x-cache", "no"}]}

  """
  @spec to_json_body(String.t(), [option()]) :: {map(), [{String.t(), String.t()}]}
  def to_json_body(topic, opts) do
    opts = validate!(opts)

    body =
      for {key, name} <- @json_fields,
          {:ok, raw} <- [Keyword.fetch(opts, key)],
          into: %{"topic" => topic},
          do: {name, json_value(key, raw)}

    {body, encode_pairs(@header_only, opts)}
  end

  @doc """
  Encodes every option to its canonical `X-` header for a raw-body publish.

  Non-ASCII values are RFC 2047 B-encoded via `rfc2047_encode/1`.

  ## Examples

      iex> ExNtfy.Publish.Options.to_headers(title: "Backup done", tags: [:warning, :backup])
      [{"x-title", "Backup done"}, {"x-tags", "warning,backup"}]

      iex> ExNtfy.Publish.Options.to_headers(delay: ~U[2026-07-05 12:00:00Z], template: true)
      [{"x-delay", "1783252800"}, {"x-template", "yes"}]

  """
  @spec to_headers([option()]) :: [{String.t(), String.t()}]
  def to_headers(opts) do
    opts = validate!(opts)
    encode_pairs(@header_names, opts)
  end

  @doc """
  Encodes every option to a query parameter for the webhook-style publish.

  Values match the header encoding, but are left raw — URL encoding covers
  UTF-8, so no RFC 2047 here.

  ## Examples

      iex> ExNtfy.Publish.Options.to_query(priority: :urgent, unified_push: true)
      [priority: "5", up: "1"]

  """
  @spec to_query([option()]) :: keyword(String.t())
  def to_query(opts) do
    opts = validate!(opts)

    for {key, name} <- @query_names,
        {:ok, raw} <- [Keyword.fetch(opts, key)],
        value = scalar(key, raw),
        do: {name, value}
  end

  @doc """
  RFC 2047 B-encodes a header value if it contains non-ASCII bytes; pure ASCII
  passes through untouched.

  ## Examples

      iex> ExNtfy.Publish.Options.rfc2047_encode("all ASCII")
      "all ASCII"

      iex> ExNtfy.Publish.Options.rfc2047_encode("Grüße 👋")
      "=?UTF-8?B?R3LDvMOfZSDwn5GL?="

  """
  @spec rfc2047_encode(String.t()) :: String.t()
  def rfc2047_encode(value) do
    if ascii?(value) do
      value
    else
      "=?UTF-8?B?" <> Base.encode64(value) <> "?="
    end
  end

  defp validate!(opts), do: NimbleOptions.validate!(opts, @schema)

  defp encode_pairs(specs, opts) do
    for {key, name} <- specs,
        {:ok, raw} <- [Keyword.fetch(opts, key)],
        value = scalar(key, raw),
        do: {name, rfc2047_encode(value)}
  end

  # Header/query encoding: returns the string value, or nil to omit the option.
  defp scalar(:priority, raw), do: raw |> priority_int() |> Integer.to_string()
  defp scalar(:tags, tags), do: Enum.map_join(tags, ",", &to_string/1)
  defp scalar(:delay, raw), do: delay_string(raw)
  defp scalar(:actions, json) when is_binary(json), do: json
  defp scalar(:actions, actions), do: Enum.map_join(actions, "; ", &Action.to_short/1)
  defp scalar(:markdown, true), do: "yes"
  defp scalar(:markdown, false), do: nil
  defp scalar(key, true) when key in [:email, :call], do: "yes"
  defp scalar(key, false) when key in [:cache, :firebase], do: "no"
  defp scalar(key, true) when key in [:cache, :firebase], do: nil
  defp scalar(:unified_push, true), do: "1"
  defp scalar(:unified_push, false), do: nil
  defp scalar(:template, true), do: "yes"
  defp scalar(:template, atom) when is_atom(atom), do: Atom.to_string(atom)
  defp scalar(_key, value), do: value

  defp json_value(:priority, raw), do: priority_int(raw)
  defp json_value(:tags, tags), do: Enum.map(tags, &to_string/1)
  defp json_value(:actions, json) when is_binary(json), do: JSON.decode!(json)
  defp json_value(:actions, actions), do: Enum.map(actions, &Action.to_json_map/1)
  defp json_value(:delay, raw), do: delay_string(raw)
  defp json_value(key, true) when key in [:email, :call], do: "yes"
  defp json_value(_key, value), do: value

  defp priority_int(int) when is_integer(int), do: int
  defp priority_int(atom), do: Map.fetch!(@priority_atoms, atom)

  defp delay_string(%DateTime{} = dt), do: dt |> DateTime.to_unix() |> Integer.to_string()
  defp delay_string(int) when is_integer(int), do: Integer.to_string(int)
  defp delay_string(string) when is_binary(string), do: string

  defp ascii?(<<c, rest::binary>>) when c < 128, do: ascii?(rest)
  defp ascii?(<<>>), do: true
  defp ascii?(_), do: false

  @doc false
  @spec validate_priority(term()) :: {:ok, 1..5 | atom()} | {:error, String.t()}
  def validate_priority(int) when is_integer(int) and int in 1..5, do: {:ok, int}
  def validate_priority(atom) when is_map_key(@priority_atoms, atom), do: {:ok, atom}

  def validate_priority(other) do
    {:error,
     "expected an integer in 1..5 or one of :min, :low, :default, :high, :max, :urgent, " <>
       "got: #{inspect(other)}"}
  end

  @doc false
  @spec validate_delay(term()) ::
          {:ok, DateTime.t() | non_neg_integer() | String.t()} | {:error, String.t()}
  def validate_delay(%DateTime{} = dt), do: {:ok, dt}
  def validate_delay(int) when is_integer(int) and int >= 0, do: {:ok, int}
  def validate_delay(string) when is_binary(string), do: {:ok, string}

  def validate_delay(other) do
    {:error,
     "expected a DateTime, a non-negative unix timestamp, or a duration/natural-language " <>
       "string, got: #{inspect(other)}"}
  end

  @doc false
  @spec validate_actions(term()) :: {:ok, String.t() | list()} | {:error, String.t()}
  def validate_actions(json) when is_binary(json), do: {:ok, json}

  def validate_actions(list) when is_list(list) and length(list) > 3 do
    {:error, "ntfy supports at most 3 actions, got #{length(list)}"}
  end

  def validate_actions(list) when is_list(list) do
    if Enum.all?(list, &action_like?/1) do
      {:ok, list}
    else
      {:error, "expected ExNtfy.Action structs or ntfy-shaped maps, got: #{inspect(list)}"}
    end
  end

  def validate_actions(other) do
    {:error, "expected a list of actions or a raw JSON string, got: #{inspect(other)}"}
  end

  @doc false
  @spec validate_string_or_yes(term()) :: {:ok, String.t() | true} | {:error, String.t()}
  def validate_string_or_yes(true), do: {:ok, true}
  def validate_string_or_yes(string) when is_binary(string), do: {:ok, string}

  def validate_string_or_yes(other),
    do: {:error, "expected a string or true, got: #{inspect(other)}"}

  @doc false
  @spec validate_template(term()) :: {:ok, true | atom() | String.t()} | {:error, String.t()}
  def validate_template(true), do: {:ok, true}
  def validate_template(atom) when atom in [:github, :grafana, :alertmanager], do: {:ok, atom}
  def validate_template(name) when is_binary(name), do: {:ok, name}

  def validate_template(other) do
    {:error,
     "expected true, :github, :grafana, :alertmanager, or a custom template name, " <>
       "got: #{inspect(other)}"}
  end

  defp action_like?(%Action{}), do: true
  defp action_like?(map), do: is_map(map) and not is_struct(map)
end
