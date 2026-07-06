defmodule ExNtfy.Handler do
  @moduledoc """
  Behaviour for the handler consumption style of `ExNtfy.subscribe/2`.

  Pass `handler: {MyHandler, init_arg}` and the subscription invokes your
  callbacks in its own process instead of sending messages to an owner:

      defmodule MyHandler do
        @behaviour ExNtfy.Handler

        @impl true
        def init(arg), do: {:ok, arg}

        @impl true
        def handle_message(%ExNtfy.Message{} = message, state) do
          IO.puts("\#{message.topic}: \#{message.message}")
          {:ok, state}
        end

        @impl true
        def handle_lifecycle(:connected, state), do: {:ok, state}
        def handle_lifecycle(_event, state), do: {:ok, state}
      end

  `handle_lifecycle/2` is optional; lifecycle events are dropped without it.
  Callbacks run inside the subscription process — an exception terminates the
  subscription (put it under your own supervisor to restart it).
  """

  alias ExNtfy.Message

  @typedoc """
  Lifecycle notifications: connection state changes, terminal `{:down,
  reason}`, and `message_clear`/`message_delete` events with their parsed
  message.
  """
  @type lifecycle_event ::
          :connected
          | :disconnected
          | {:down, term()}
          | {:message_clear | :message_delete, Message.t()}

  @doc "Invoked once at subscription start; returns the initial handler state."
  @callback init(arg :: term()) :: {:ok, state :: term()}

  @doc "Invoked for every `:message` event."
  @callback handle_message(Message.t(), state :: term()) :: {:ok, state :: term()}

  @doc "Optional: invoked for lifecycle events (see `t:lifecycle_event/0`)."
  @callback handle_lifecycle(lifecycle_event(), state :: term()) :: {:ok, state :: term()}

  @optional_callbacks handle_lifecycle: 2
end
