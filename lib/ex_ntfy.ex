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

  ## Attachments

  Attach by URL with the `:attach` option, or upload a binary with
  `publish_file/3` — iodata, a stream, or `{:file, path}` (streamed from
  disk; filename defaults to the basename):

      ExNtfy.publish_file("mytopic", {:file, "/tmp/report.pdf"},
        message: "Monthly report attached",
        title: "Reports"
      )

      {:ok, message} = ExNtfy.publish_file("mytopic", png_bytes, filename: "graph.png")
      message.attachment.url
      #=> "https://ntfy.sh/file/oaFAdEY1KC.png"

  ## Lifecycle: update, clear, delete

  Messages sharing a sequence ID form a sequence; clients show the latest
  state. The simplest idiom is to reuse the `id` of the message you published:

      {:ok, message} = ExNtfy.publish("deploys", "Deploy started…")

      # Update it in place as things progress (the returned id is the sequence id)
      ExNtfy.update("deploys", message.id, "Deploy at 80%…")
      ExNtfy.update("deploys", message.id, "Deploy finished ✅")

      # Then dismiss it from clients, or delete it outright
      ExNtfy.clear("deploys", message.id)
      ExNtfy.delete("deploys", message.id)

  Alternatively pick your own sequence ID up front
  (`ExNtfy.publish("deploys", "…", sequence_id: "deploy-42")`) and use it for
  every follow-up.

  ## Polling

  Fetch cached messages without holding a connection open (see
  `ExNtfy.Subscribe.Options` for the full `since`/filter surface):

      # Everything cached for one or more topics
      {:ok, messages} = ExNtfy.poll("mytopic")
      {:ok, messages} = ExNtfy.poll(["alerts", "backups"], since: "10m")

      # Resume after the last message you processed
      ExNtfy.poll("mytopic", since: last_message.id)

      # Filters: priority is any-match, tags must all match
      ExNtfy.poll("mytopic", priority: [:high, :urgent], tags: [:warning], scheduled: true)

  ## Subscribing (streaming)

  Long-lived subscriptions reconnect automatically with backoff, resume from
  the last seen message (`since=<id>`), and watch for dead connections via a
  keepalive watchdog. Three consumption styles:

  **Message-passing** — events arrive in the calling process's mailbox:

      {:ok, sub} = ExNtfy.subscribe("alerts", since: "10m")

      receive do
        {:ntfy, ^sub, %ExNtfy.Message{} = message} -> handle(message)
        {:ntfy_lifecycle, ^sub, :connected} -> :ok
        {:ntfy_lifecycle, ^sub, :disconnected} -> :ok
        {:ntfy_lifecycle, ^sub, {:message_clear, message}} -> dismiss(message)
        {:ntfy_lifecycle, ^sub, {:down, reason}} -> react(reason)
      end

      ExNtfy.unsubscribe(sub)

  The subscription stops when its owner (the caller, or `owner:`) dies.

  **Handler behaviour** — callbacks run in the subscription process; put it
  in your supervision tree:

      children = [
        {ExNtfy.Subscription,
         topics: ["alerts", "backups"],
         handler: {MyApp.NtfyHandler, []},
         auth: {:token, "tk_..."},
         name: MyApp.NtfySub}
      ]

  See `ExNtfy.Handler` for the callbacks. A crashing handler takes the
  subscription down with it — the supervisor restarts both.

  **Lazy stream** — blocks the calling process, halts cleanly:

      ExNtfy.stream("alerts")
      |> Stream.filter(&(&1.priority >= 4))
      |> Enum.take(5)

  All subscribe filters (`ExNtfy.Subscribe.Options`) and client options
  apply; `format: :sse | :raw | :ws` selects the other transports (`:raw`
  carries bodies only — no metadata, no resume; `:ws` subscribes over
  WebSocket and requires the optional `:mint_web_socket` dependency).

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

  alias ExNtfy.{Poller, Publisher, Subscription}

  @doc "Publishes a message as JSON. See `ExNtfy.Publisher.publish/3`."
  defdelegate publish(topic, message, opts \\ []), to: Publisher

  @doc "Like `publish/3`, but raises `ExNtfy.Error` on failure. See `ExNtfy.Publisher.publish!/3`."
  defdelegate publish!(topic, message, opts \\ []), to: Publisher

  @doc "Publishes a raw body with options as headers. See `ExNtfy.Publisher.publish_raw/3`."
  defdelegate publish_raw(topic, body, opts \\ []), to: Publisher

  @doc "Webhook-style GET publish. See `ExNtfy.Publisher.trigger/2`."
  defdelegate trigger(topic, opts \\ []), to: Publisher

  @doc "Uploads a binary attachment. See `ExNtfy.Publisher.publish_file/3`."
  defdelegate publish_file(topic, body, opts \\ []), to: Publisher

  @doc "Like `publish_file/3`, but raises on failure. See `ExNtfy.Publisher.publish_file!/3`."
  defdelegate publish_file!(topic, body, opts \\ []), to: Publisher

  @doc "Updates a notification via its sequence ID. See `ExNtfy.Publisher.update/4`."
  defdelegate update(topic, sequence_id, message, opts \\ []), to: Publisher

  @doc "Clears (dismisses) a delivered notification. See `ExNtfy.Publisher.clear/3`."
  defdelegate clear(topic, sequence_id, opts \\ []), to: Publisher

  @doc "Deletes a notification from clients. See `ExNtfy.Publisher.delete/3`."
  defdelegate delete(topic, sequence_id, opts \\ []), to: Publisher

  @doc "Fetches cached messages one-shot. See `ExNtfy.Poller.poll/2`."
  defdelegate poll(topics, opts \\ []), to: Poller

  @doc "Like `poll/2`, but raises on failure. See `ExNtfy.Poller.poll!/2`."
  defdelegate poll!(topics, opts \\ []), to: Poller

  @doc "Starts a streaming subscription. See `ExNtfy.Subscription.subscribe/2`."
  defdelegate subscribe(topics, opts \\ []), to: Subscription

  @doc "Stops a subscription cleanly. See `ExNtfy.Subscription.unsubscribe/1`."
  defdelegate unsubscribe(subscription), to: Subscription

  @doc "A lazy stream of messages. See `ExNtfy.Subscription.stream/2`."
  defdelegate stream(topics, opts \\ []), to: Subscription
end
