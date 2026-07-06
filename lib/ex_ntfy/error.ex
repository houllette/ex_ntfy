defmodule ExNtfy.Error do
  @moduledoc """
  The error type for all ExNtfy failures.

  HTTP-level failures carry ntfy's JSON error fields (`code`, `http`, `error`,
  `link`); transport-level failures carry the underlying exception in `reason`,
  and a 2xx response whose body isn't a parsable message carries
  `{:invalid_response, details}` there. Implements `Exception`, so it can be
  raised or rendered with `Exception.message/1`.
  """

  defexception [:code, :http, :error, :link, :reason]

  @type t :: %__MODULE__{
          code: integer() | nil,
          http: integer() | nil,
          error: String.t() | nil,
          link: String.t() | nil,
          reason: Exception.t() | {:invalid_response, term()} | nil
        }

  @doc """
  Builds an error from a non-2xx HTTP response.

  Accepts the body as an already-decoded map (Req decodes JSON responses), a
  raw JSON binary, a plain-text binary, or an empty/absent body. The `http`
  field prefers ntfy's own `"http"` value, falling back to the response status.
  """
  @spec from_response(non_neg_integer(), map() | binary() | nil) :: t()
  def from_response(status, body) when is_struct(body) do
    # e.g. an unconsumed %Req.Response.Async{} from a streaming request —
    # there is no error JSON to read, only the status.
    %__MODULE__{http: status}
  end

  def from_response(status, body) when is_map(body) do
    %__MODULE__{
      code: body["code"],
      http: body["http"] || status,
      error: body["error"],
      link: body["link"]
    }
  end

  def from_response(status, body) when is_binary(body) do
    case JSON.decode(body) do
      {:ok, map} when is_map(map) -> from_response(status, map)
      _ -> %__MODULE__{http: status, error: presence(body)}
    end
  end

  def from_response(status, nil), do: %__MODULE__{http: status}

  @doc """
  Wraps a transport-level exception (e.g. `Req.TransportError`).
  """
  @spec from_exception(Exception.t()) :: t()
  def from_exception(exception) when is_exception(exception) do
    %__MODULE__{reason: exception}
  end

  @impl Exception
  def message(%__MODULE__{reason: reason}) when is_exception(reason) do
    "ntfy request failed: #{Exception.message(reason)}"
  end

  def message(%__MODULE__{reason: reason}) when not is_nil(reason) do
    "ntfy request failed: #{inspect(reason)}"
  end

  def message(%__MODULE__{} = e) do
    parts = [
      "ntfy error",
      e.code && " #{e.code}",
      e.http && " (HTTP #{e.http})",
      e.error && ": #{e.error}",
      e.link && " — see #{e.link}"
    ]

    parts
    |> Enum.reject(&is_nil/1)
    |> Enum.join()
  end

  defp presence(""), do: nil
  defp presence(binary), do: binary
end
