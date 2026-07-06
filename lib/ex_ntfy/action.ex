defmodule ExNtfy.Action do
  @moduledoc """
  An ntfy action button.

  A single struct covers all four action types (`:view`, `:broadcast`, `:http`,
  `:copy`) with the union of their fields; fields not applicable to a type are
  `nil`. Unknown action types are kept as `{:unknown, string}` rather than
  raising, since the server may add types over time.

  | Type         | Required fields  | Optional fields                         |
  |--------------|------------------|-----------------------------------------|
  | `:view`      | `label`, `url`   | `clear`                                 |
  | `:broadcast` | `label`          | `intent`, `extras`, `clear`             |
  | `:http`      | `label`, `url`   | `method`, `headers`, `body`, `clear`    |
  | `:copy`      | `label`, `value` | `clear`                                 |
  """

  defstruct [
    :type,
    :id,
    :label,
    :url,
    :method,
    :headers,
    :body,
    :intent,
    :extras,
    :value,
    clear: false
  ]

  @type type :: :view | :broadcast | :http | :copy | {:unknown, String.t()}

  @type t :: %__MODULE__{
          type: type() | nil,
          id: String.t() | nil,
          label: String.t() | nil,
          url: String.t() | nil,
          method: String.t() | nil,
          headers: %{optional(String.t()) => String.t()} | nil,
          body: String.t() | nil,
          intent: String.t() | nil,
          extras: %{optional(String.t()) => String.t()} | nil,
          value: String.t() | nil,
          clear: boolean()
        }

  @known_types %{
    "view" => :view,
    "broadcast" => :broadcast,
    "http" => :http,
    "copy" => :copy
  }

  @doc """
  Builds an action from a decoded JSON map (the incoming `"action"` key names
  the type).

  Lenient: missing fields become `nil` (`clear` defaults to `false`), unknown
  fields are ignored.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      type: parse_type(map["action"]),
      id: map["id"],
      label: map["label"],
      url: map["url"],
      method: map["method"],
      headers: map["headers"],
      body: map["body"],
      intent: map["intent"],
      extras: map["extras"],
      value: map["value"],
      clear: map["clear"] || false
    }
  end

  @doc """
  Encodes an action to the ntfy JSON object shape (the outgoing counterpart of
  `from_map/1` — fixture maps round-trip exactly).

  `nil` fields and a `false` `clear` are omitted; plain ntfy-shaped maps pass
  through untouched.

  ## Examples

      iex> ExNtfy.Action.to_json_map(%ExNtfy.Action{type: :copy, label: "Copy", value: "abc"})
      %{"action" => "copy", "label" => "Copy", "value" => "abc"}

  """
  @spec to_json_map(t() | map()) :: map()
  def to_json_map(%__MODULE__{} = action) do
    %{
      "action" => type_string(action.type),
      "id" => action.id,
      "label" => action.label,
      "url" => action.url,
      "method" => action.method,
      "headers" => action.headers,
      "body" => action.body,
      "intent" => action.intent,
      "extras" => action.extras,
      "value" => action.value,
      "clear" => action.clear || nil
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  def to_json_map(map) when is_map(map), do: map

  @doc """
  Encodes an action in ntfy's short header format (§1.5): `key=value` pairs
  joined by `, `, with `headers` and `extras` maps flattened to
  `headers.<name>=` / `extras.<key>=` (keys sorted for determinism).

  Values containing `,`, `;`, or quotes are quoted — double quotes by default,
  single quotes when the value itself contains a double quote. `clear` appears
  only when `true`; `id` is server-assigned and never emitted.

  ## Examples

      iex> ExNtfy.Action.to_short(%ExNtfy.Action{type: :view, label: "Open", url: "https://x.io"})
      "action=view, label=Open, url=https://x.io"

  """
  @spec to_short(t() | map()) :: String.t()
  def to_short(%__MODULE__{} = action) do
    fields =
      [{"action", type_string(action.type)}, {"label", action.label}] ++
        [{"url", action.url}, {"method", action.method}] ++
        flatten("headers", action.headers) ++
        [{"body", action.body}, {"intent", action.intent}] ++
        flatten("extras", action.extras) ++
        [{"value", action.value}] ++
        if action.clear, do: [{"clear", "true"}], else: []

    fields
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.map_join(", ", fn {key, value} -> key <> "=" <> quote_short(value) end)
  end

  def to_short(map) when is_map(map), do: map |> from_map() |> to_short()

  defp parse_type(nil), do: nil
  defp parse_type(name) when is_map_key(@known_types, name), do: @known_types[name]
  defp parse_type(name) when is_binary(name), do: {:unknown, name}

  defp type_string(nil), do: nil
  defp type_string({:unknown, name}), do: name
  defp type_string(atom), do: Atom.to_string(atom)

  defp flatten(_prefix, nil), do: []

  defp flatten(prefix, map) do
    map |> Enum.sort() |> Enum.map(fn {key, value} -> {prefix <> "." <> key, value} end)
  end

  defp quote_short(value) do
    cond do
      not String.contains?(value, [",", ";", "\"", "'"]) -> value
      String.contains?(value, "\"") -> "'" <> value <> "'"
      true -> "\"" <> value <> "\""
    end
  end
end
