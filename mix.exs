defmodule ExNtfy.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/houllette/ex_ntfy"

  def project do
    [
      app: :ex_ntfy,
      version: @version,
      # 1.18 is the floor: it introduced the built-in JSON module.
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "An Elixir SDK for ntfy.sh — publish and subscribe to push notifications.",
      package: package(),
      docs: docs(),
      test_coverage: [tool: ExCoveralls],
      # Mint.WebSocket comes from the optional :mint_web_socket dependency;
      # all references are runtime and guarded by Stream.WS.ensure_available!/0.
      elixirc_options: [no_warn_undefined: [Mint.WebSocket]],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/ex_ntfy.plt"}
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.6"},
      {:nimble_options, "~> 1.1"},
      {:telemetry, "~> 1.4"},
      # optional: WebSocket transport (format: :ws)
      {:mint_web_socket, "~> 1.0", optional: true},
      # dev/test
      {:bandit, "~> 1.12", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:websock_adapter, "~> 0.6", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      # Keep the tarball lean: no plan/, test/, guides/, or CI files.
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE .formatter.exs),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "ntfy" => "https://ntfy.sh",
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "ExNtfy",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "guides/publishing.md",
        "guides/subscriptions.md",
        "guides/testing.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Guides: ~r{guides/}
      ],
      groups_for_modules: [
        Publishing: [ExNtfy.Publisher, ExNtfy.Publish.Options],
        "Polling & Subscribing": [
          ExNtfy.Poller,
          ExNtfy.Subscription,
          ExNtfy.Subscribe.Options,
          ExNtfy.Handler,
          ExNtfy.Stream.WS
        ],
        Types: [ExNtfy.Message, ExNtfy.Action, ExNtfy.Attachment, ExNtfy.Error],
        "Client & Config": [ExNtfy.Client, ExNtfy.Config]
      ]
    ]
  end
end
