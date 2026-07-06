defmodule ExNtfy.ClientAppConfigTest do
  # Mutates :ex_ntfy application env, so must not run alongside async tests.
  # ExUnit runs sync modules after all async modules finish, keeping this safe.
  use ExUnit.Case, async: false

  import ExNtfy.TestHelpers

  alias ExNtfy.Client

  setup do
    on_exit(fn ->
      for {key, _} <- Application.get_all_env(:ex_ntfy) do
        Application.delete_env(:ex_ntfy, key)
      end
    end)
  end

  test "app config overrides defaults" do
    Application.put_env(:ex_ntfy, :base_url, "https://cfg.example.com")

    opts =
      req_stub(fn conn ->
        assert conn.host == "cfg.example.com"
        Req.Test.json(conn, %{})
      end)

    assert {:ok, _} = Client.request(opts, url: "/mytopic", method: :get)
  end

  test "per-call opts override app config" do
    Application.put_env(:ex_ntfy, :base_url, "https://cfg.example.com")

    opts =
      req_stub(fn conn ->
        assert conn.host == "opt.example.com"
        Req.Test.json(conn, %{})
      end)

    assert {:ok, _} =
             Client.request([base_url: "https://opt.example.com"] ++ opts,
               url: "/mytopic",
               method: :get
             )
  end
end
