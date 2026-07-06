defmodule ExNtfy.SubscriptionWSUnavailableTest do
  # async: false — mutates the :ws_dependency app env, which the WS transport
  # guard reads. ExUnit runs sync modules after all async ones.
  use ExUnit.Case, async: false

  test "a clear error fires at subscribe/2 time when mint_web_socket is missing" do
    Application.put_env(:ex_ntfy, :ws_dependency, ExNtfy.NoSuchDependency)
    on_exit(fn -> Application.delete_env(:ex_ntfy, :ws_dependency) end)

    assert_raise ArgumentError, ~r/mint_web_socket/, fn ->
      ExNtfy.subscribe("mytopic", format: :ws)
    end
  end
end
