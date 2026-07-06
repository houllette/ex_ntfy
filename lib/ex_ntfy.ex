defmodule ExNtfy do
  @moduledoc """
  An Elixir SDK for [ntfy](https://ntfy.sh) — a simple HTTP-based pub-sub
  notification service.

  ExNtfy lets you publish notifications to ntfy topics and subscribe to
  messages, targeting either the public ntfy.sh instance or a self-hosted
  server.

  ## Publishing

      # The simplest possible publish
      {:ok, message} = ExNtfy.publish("mytopic", "Backup completed 🎉")

      # With options (see `ExNtfy.Publish.Options` for the full list)
      ExNtfy.publish("alerts", "Disk almost full",
        title: "Server alert",
        priority: :urgent,
        tags: [:warning, :floppy_disk],
        click: "https://grafana.example.com/d/disk"
      )

      # Action buttons
      ExNtfy.publish("deploys", "Deploy finished",
        actions: [
          %ExNtfy.Action{type: :view, label: "Open", url: "https://example.com/deploys/42"}
        ]
      )

      # Raw body + templating: forward a webhook payload and let the server
      # render it (reference §1.6)
      ExNtfy.publish_raw("builds", github_webhook_json, template: :github)

      # Webhook-style GET, e.g. from a curl one-liner or cron job
      ExNtfy.trigger("mytopic", message: "cron ran", tags: [:clock])

  Client options mix into the same keyword list — for a self-hosted server
  with authentication:

      ExNtfy.publish("private", "hi",
        base_url: "https://ntfy.example.com",
        auth: {:token, "tk_..."}
      )

  `publish/3` returns `{:ok, %ExNtfy.Message{}}` (the created message as the
  server recorded it) or `{:error, %ExNtfy.Error{}}`; `publish!/3` returns the
  message or raises.
  """

  alias ExNtfy.Publisher

  @doc "Publishes a message as JSON. See `ExNtfy.Publisher.publish/3`."
  defdelegate publish(topic, message, opts \\ []), to: Publisher

  @doc "Like `publish/3`, but raises `ExNtfy.Error` on failure. See `ExNtfy.Publisher.publish!/3`."
  defdelegate publish!(topic, message, opts \\ []), to: Publisher

  @doc "Publishes a raw body with options as headers. See `ExNtfy.Publisher.publish_raw/3`."
  defdelegate publish_raw(topic, body, opts \\ []), to: Publisher

  @doc "Webhook-style GET publish. See `ExNtfy.Publisher.trigger/2`."
  defdelegate trigger(topic, opts \\ []), to: Publisher
end
