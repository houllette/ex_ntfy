defmodule ExNtfy.Client do
  @moduledoc """
  Req-based HTTP client for the ntfy API.

  `new/1` builds a configured `Req.Request` from `ExNtfy.Config` options;
  `request/2` executes it and normalizes failures into `ExNtfy.Error`. Feature
  modules (publish, poll, subscribe) build request options and call
  `request/2` — callers are not expected to use Req directly.
  """

  alias ExNtfy.{Config, Error}

  @version Mix.Project.config()[:version]
  @user_agent "ex_ntfy/#{@version} (Elixir)"

  @doc """
  Builds a configured `Req.Request`.

  Options are resolved through `ExNtfy.Config.resolve/2` (per-call opts >
  application config > defaults). `:req_options` is merged last via
  `Req.merge/2`, so anything in it — including `plug:` for tests — wins over
  the computed defaults.
  """
  @spec new([Config.option()]) :: Req.Request.t()
  def new(opts \\ []) do
    config = Config.resolve(opts)
    {auth_headers, auth_params} = encode_auth(config[:auth], config[:auth_via])

    base =
      [
        base_url: config[:base_url],
        headers: [{"user-agent", @user_agent} | auth_headers]
      ]
      |> put_present(:params, auth_params)
      |> put_present(:receive_timeout, config[:receive_timeout])
      |> put_present(:retry, config[:retry])

    base
    |> Req.new()
    |> Req.merge(config[:req_options])
  end

  @doc """
  Executes a request and normalizes the outcome.

  Accepts either a `Req.Request` from `new/1` or a keyword list of client
  options (built into a request on the fly). `req_opts` are per-request Req
  options such as `:method`, `:url`, `:body`, `:params`.

  Returns `{:ok, response}` for 2xx responses; any other status becomes
  `{:error, %ExNtfy.Error{}}` via `ExNtfy.Error.from_response/2`, and
  transport failures become `{:error, %ExNtfy.Error{reason: exception}}`.
  """
  @spec request(Req.Request.t() | [Config.option()], keyword()) ::
          {:ok, Req.Response.t()} | {:error, Error.t()}
  def request(req_or_opts, req_opts \\ [])

  def request(%Req.Request{} = req, req_opts) do
    case Req.request(req, req_opts) do
      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        {:ok, response}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, Error.from_response(status, body)}

      {:error, exception} ->
        {:error, Error.from_exception(exception)}
    end
  end

  def request(opts, req_opts) when is_list(opts) do
    opts |> new() |> request(req_opts)
  end

  # Also used by the WebSocket transport, which builds its upgrade request
  # without Req.
  @doc false
  @spec user_agent() :: String.t()
  def user_agent, do: @user_agent

  @doc false
  @spec encode_auth(Config.auth(), :header | :query) ::
          {[{String.t(), String.t()}], keyword() | nil}
  def encode_auth(nil, _via), do: {[], nil}

  def encode_auth(auth, :header), do: {[{"authorization", header_value(auth)}], nil}

  def encode_auth(auth, :query) do
    {[], [auth: Base.url_encode64(header_value(auth), padding: false)]}
  end

  defp header_value({:basic, user, pass}), do: "Basic " <> Base.encode64("#{user}:#{pass}")
  defp header_value({:token, token}), do: "Bearer " <> token

  defp put_present(keyword, _key, nil), do: keyword
  defp put_present(keyword, key, value), do: Keyword.put(keyword, key, value)
end
