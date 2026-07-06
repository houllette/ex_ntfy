defmodule ExNtfy.Message do
  @moduledoc """
  A received ntfy message — the JSON schema shared by publish responses and
  subscribe events.

  Parsing is lenient by design: the server adds fields over time, so unknown
  keys never crash and the original decoded map is retained in `raw`. Known
  event names become atoms; unrecognized ones become `{:unknown, string}`.
  """

  alias ExNtfy.{Action, Attachment}

  @enforce_keys [:id, :time, :event, :topic]
  defstruct [
    :id,
    :time,
    :event,
    :topic,
    :message,
    :title,
    :tags,
    :priority,
    :click,
    :actions,
    :attachment,
    :expires,
    :sequence_id,
    :icon,
    :content_type,
    :raw
  ]

  @type event ::
          :open
          | :keepalive
          | :message
          | :message_clear
          | :message_delete
          | :poll_request
          | {:unknown, String.t()}

  @type t :: %__MODULE__{
          id: String.t(),
          time: integer(),
          event: event(),
          topic: String.t(),
          message: String.t() | nil,
          title: String.t() | nil,
          tags: [String.t()] | nil,
          priority: 1..5 | nil,
          click: String.t() | nil,
          actions: [Action.t()] | nil,
          attachment: Attachment.t() | nil,
          expires: integer() | nil,
          sequence_id: String.t() | nil,
          icon: String.t() | nil,
          content_type: String.t() | nil,
          raw: map()
        }

  @always_present ~w(id time event topic)

  @known_events %{
    "open" => :open,
    "keepalive" => :keepalive,
    "message" => :message,
    "message_clear" => :message_clear,
    "message_delete" => :message_delete,
    "poll_request" => :poll_request
  }

  @doc """
  Builds a message from a decoded JSON map.

  Returns `{:error, {:missing_fields, fields}}` when any of the always-present
  fields (`id`, `time`, `event`, `topic`) are absent; everything else is
  optional and defaults to `nil`.

  ## Examples

      iex> {:ok, msg} = ExNtfy.Message.from_map(%{
      ...>   "id" => "sPs71M8A2T",
      ...>   "time" => 1735920000,
      ...>   "event" => "message",
      ...>   "topic" => "mytopic",
      ...>   "message" => "hi"
      ...> })
      iex> {msg.event, msg.message, msg.priority}
      {:message, "hi", nil}

  """
  @spec from_map(map()) :: {:ok, t()} | {:error, {:missing_fields, [String.t()]}}
  def from_map(map) when is_map(map) do
    case Enum.filter(@always_present, &(map[&1] == nil)) do
      [] -> {:ok, build(map)}
      missing -> {:error, {:missing_fields, missing}}
    end
  end

  @doc """
  Decodes a JSON binary (e.g. one NDJSON line from a `/json` subscription) into
  a message.

  Returns `{:error, reason}` on invalid JSON, non-object JSON, or missing
  always-present fields.
  """
  @spec from_json(binary()) :: {:ok, t()} | {:error, term()}
  def from_json(binary) when is_binary(binary) do
    case JSON.decode(binary) do
      {:ok, map} when is_map(map) -> from_map(map)
      {:ok, other} -> {:error, {:not_an_object, other}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build(map) do
    %__MODULE__{
      id: map["id"],
      time: map["time"],
      event: parse_event(map["event"]),
      topic: map["topic"],
      message: map["message"],
      title: map["title"],
      tags: map["tags"],
      priority: map["priority"],
      click: map["click"],
      actions: parse_actions(map["actions"]),
      attachment: parse_attachment(map["attachment"]),
      expires: map["expires"],
      sequence_id: map["sequence_id"],
      icon: map["icon"],
      content_type: map["content_type"],
      raw: map
    }
  end

  defp parse_event(name) when is_map_key(@known_events, name), do: @known_events[name]
  defp parse_event(name) when is_binary(name), do: {:unknown, name}

  defp parse_actions(nil), do: nil
  defp parse_actions(actions) when is_list(actions), do: Enum.map(actions, &Action.from_map/1)

  defp parse_attachment(nil), do: nil
  defp parse_attachment(attachment) when is_map(attachment), do: Attachment.from_map(attachment)
end
