# Live integration tests hit ntfy.sh over the network; run them explicitly
# with `mix test --only live`.
ExUnit.configure(exclude: [:live])
ExUnit.start()
