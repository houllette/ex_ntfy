defmodule ExNtfy.Config do
  @moduledoc """
  Resolves client configuration with a fixed precedence:
  per-call options override application config (`config :ex_ntfy, ...`),
  which overrides library defaults.
  """

  @config_keys [:base_url, :auth, :auth_via, :receive_timeout, :retry, :req_options]

  @schema NimbleOptions.new!(
            base_url: [
              type: :string,
              default: "https://ntfy.sh",
              doc: "Base URL of the ntfy server."
            ],
            auth: [
              type: {:custom, __MODULE__, :validate_auth, []},
              default: nil,
              doc:
                "Credentials: `{:basic, user, pass}`, `{:token, \"tk_...\"}`, or `nil` for none."
            ],
            auth_via: [
              type: {:in, [:header, :query]},
              default: :header,
              doc:
                "How to transmit credentials: the `Authorization` header (default) or " <>
                  "the `?auth=` query parameter (for clients that cannot set headers)."
            ],
            receive_timeout: [
              type: :timeout,
              doc: "Socket receive timeout in milliseconds, passed through to Req."
            ],
            retry: [
              type: :any,
              doc: "Pass-through to Req's `:retry` option."
            ],
            req_options: [
              type: :keyword_list,
              default: [],
              doc: "Escape hatch: extra Req options merged last (e.g. `plug:` in tests)."
            ]
          )

  @typedoc "Client credentials."
  @type auth :: {:basic, String.t(), String.t()} | {:token, String.t()} | nil

  @typedoc "A single client configuration option."
  @type option ::
          {:base_url, String.t()}
          | {:auth, auth()}
          | {:auth_via, :header | :query}
          | {:receive_timeout, timeout()}
          | {:retry, term()}
          | {:req_options, keyword()}

  @doc """
  Merges `opts` over `app_env` over defaults and validates the result.

  `app_env` defaults to `Application.get_all_env(:ex_ntfy)`; unknown keys in it
  are ignored (the app env may hold unrelated entries), while unknown keys in
  `opts` raise `NimbleOptions.ValidationError`.

  ## Examples

      iex> ExNtfy.Config.resolve()[:base_url]
      "https://ntfy.sh"

      iex> ExNtfy.Config.resolve([], base_url: "https://cfg.example")[:base_url]
      "https://cfg.example"

      iex> ExNtfy.Config.resolve([base_url: "http://localhost:8080"],
      ...>   base_url: "https://cfg.example"
      ...> )[:base_url]
      "http://localhost:8080"

  """
  @spec resolve([option()], keyword()) :: [option()]
  def resolve(opts \\ [], app_env \\ Application.get_all_env(:ex_ntfy)) do
    app_env
    |> Keyword.take(@config_keys)
    |> Keyword.merge(opts)
    |> NimbleOptions.validate!(@schema)
  end

  @doc false
  @spec validate_auth(term()) :: {:ok, auth()} | {:error, String.t()}
  def validate_auth(nil), do: {:ok, nil}

  def validate_auth({:basic, user, pass}) when is_binary(user) and is_binary(pass),
    do: {:ok, {:basic, user, pass}}

  def validate_auth({:token, token}) when is_binary(token), do: {:ok, {:token, token}}

  def validate_auth(other) do
    {:error, "expected {:basic, user, pass}, {:token, token}, or nil, got: #{inspect(other)}"}
  end
end
