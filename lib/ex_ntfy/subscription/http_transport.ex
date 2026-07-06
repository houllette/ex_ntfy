defmodule ExNtfy.Subscription.HTTPTransport do
  @moduledoc """
  The default `ExNtfy.Subscription.Transport`: a streaming HTTP request via
  Req's `into: :self` — chunks arrive as messages parsed with
  `Req.parse_message/2`. Used by the `:json`, `:sse`, and `:raw` formats.

  Req's own retry is disabled on the request; the subscription's reconnect
  loop is in charge.
  """

  @behaviour ExNtfy.Subscription.Transport

  alias ExNtfy.{Client, Error}

  @impl ExNtfy.Subscription.Transport
  def connect(client_opts, path, params) do
    request_opts = [method: :get, url: path, params: params, into: :self, retry: false]

    case Client.request(Client.new(client_opts), request_opts) do
      {:ok, %Req.Response{} = resp} -> {:ok, resp}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  @impl ExNtfy.Subscription.Transport
  def handle_message(message, resp) do
    case Req.parse_message(resp, message) do
      {:ok, parts} -> collect_parts(parts, resp)
      {:error, reason} -> {:error, reason}
      :unknown -> :unknown
    end
  end

  @impl ExNtfy.Subscription.Transport
  def close(resp) do
    Req.cancel_async_response(resp)
    :ok
  end

  defp collect_parts(parts, resp) do
    {chunks, closed?} =
      Enum.reduce(parts, {[], false}, fn
        {:data, data}, {chunks, closed?} -> {[data | chunks], closed?}
        :done, {chunks, _closed?} -> {chunks, true}
        {:trailers, _trailers}, acc -> acc
      end)

    chunks = Enum.reverse(chunks)

    if closed? do
      {:closed, chunks, :closed}
    else
      {:data, chunks, resp}
    end
  end
end
