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

  defp parse_type(nil), do: nil
  defp parse_type(name) when is_map_key(@known_types, name), do: @known_types[name]
  defp parse_type(name) when is_binary(name), do: {:unknown, name}
end
