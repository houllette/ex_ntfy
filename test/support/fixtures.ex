defmodule ExNtfy.Fixtures do
  @moduledoc """
  Real ntfy payloads (from `plan/ntfy-api-reference.md` examples) shared across tests.
  """

  @doc "A `message` event exercising every documented field (§2.4)."
  def full_message_map do
    %{
      "id" => "sPs71M8A2T",
      "time" => 1_735_920_000,
      "expires" => 1_735_963_200,
      "event" => "message",
      "topic" => "mytopic",
      "sequence_id" => "deploy-42",
      "message" => "Deploy finished **successfully**",
      "title" => "Deploy status",
      "tags" => ["tada", "deploy"],
      "priority" => 4,
      "click" => "https://example.com/deploys/42",
      "icon" => "https://example.com/icon.png",
      "content_type" => "text/markdown",
      "actions" => [
        view_action_map(),
        broadcast_action_map(),
        http_action_map(),
        copy_action_map()
      ],
      "attachment" => attachment_map()
    }
  end

  @doc "A minimal `keepalive` event — only the always-present fields."
  def keepalive_map do
    %{
      "id" => "F2ZoyEBBg9",
      "time" => 1_735_920_011,
      "event" => "keepalive",
      "topic" => "mytopic"
    }
  end

  @doc "An `open` event; `topic` may be a comma-separated list (§2.4)."
  def open_map do
    %{
      "id" => "hwQ2YpKdmg",
      "time" => 1_735_919_999,
      "event" => "open",
      "topic" => "topic1,topic2"
    }
  end

  @doc "A server-hosted upload attachment (§1.4) — all five fields present."
  def attachment_map do
    %{
      "name" => "flower.jpg",
      "url" => "https://ntfy.sh/file/oaFAdEY1KC.jpg",
      "type" => "image/jpeg",
      "size" => 12_345,
      "expires" => 1_735_963_200
    }
  end

  def view_action_map do
    %{
      "id" => "action-1",
      "action" => "view",
      "label" => "Open portal",
      "url" => "https://example.com/deploys/42",
      "clear" => true
    }
  end

  def broadcast_action_map do
    %{
      "id" => "action-2",
      "action" => "broadcast",
      "label" => "Take picture",
      "intent" => "io.heckel.ntfy.USER_ACTION",
      "extras" => %{"cmd" => "pic", "camera" => "front"}
    }
  end

  def http_action_map do
    %{
      "id" => "action-3",
      "action" => "http",
      "label" => "Close door",
      "url" => "https://api.example.com/door",
      "method" => "PUT",
      "headers" => %{"Authorization" => "Bearer zAzsx1sk.."},
      "body" => ~s({"action":"close"})
    }
  end

  def copy_action_map do
    %{
      "id" => "action-4",
      "action" => "copy",
      "label" => "Copy code",
      "value" => "abc123"
    }
  end

  @doc "JSON body returned by a successful publish (§1.1)."
  def publish_response_map do
    %{
      "id" => "xE73Iyuabi",
      "time" => 1_673_542_291,
      "expires" => 1_673_585_491,
      "event" => "message",
      "topic" => "mytopic",
      "message" => "triggered"
    }
  end

  @doc "ntfy JSON error body for HTTP 429 (§1.8)."
  def error_429_map do
    %{
      "code" => 42_901,
      "http" => 429,
      "error" => "limit reached: too many requests, please be nice",
      "link" => "https://ntfy.sh/docs/publish/#limitations"
    }
  end
end
