defmodule ExNtfy.Subscription.Transport do
  # The connection boundary ExNtfy.Subscription drives — everything else
  # (reconnect/backoff, since resume, idle watchdog, delivery) is
  # transport-agnostic. Implementations own one connection whose incoming
  # Erlang messages arrive in the subscription's handle_info/2 and are handed
  # to handle_message/2; the payload units they yield are fed to the format's
  # stream parser. connect/3 errors distinguish fate: an ExNtfy.Error with
  # reason: nil is an HTTP-level rejection (fatal — the subscription stops);
  # any other error is transport-level and goes through the reconnect flow.
  @moduledoc false

  alias ExNtfy.Error

  @typedoc "Opaque per-connection state owned by the transport."
  @type conn :: term()

  @doc """
  Opens a connection for the given client options, request path, and query
  params. Called from the subscription process (blocking it until the
  connection is established or fails).
  """
  @callback connect(client_opts :: keyword(), path :: String.t(), params :: keyword()) ::
              {:ok, conn()} | {:error, Error.t()}

  @doc """
  Interprets one Erlang message. Returns payload units for the parser, a
  close (with any final units), a transport error, or `:unknown` for
  messages that don't belong to this connection.
  """
  @callback handle_message(message :: term(), conn()) ::
              {:data, [binary()], conn()}
              | {:closed, [binary()], reason :: term()}
              | {:error, reason :: term()}
              | :unknown

  @doc "Tears the connection down (best effort)."
  @callback close(conn()) :: :ok
end
