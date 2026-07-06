# Elixir Formatter Configuration
# https://hexdocs.pm/mix/Mix.Tasks.Format.html

[
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs}",
    "scripts/**/*.exs"
  ],
  line_length: 120,
  import_deps: [:tesla],
  locals_without_parens: []
]
