defmodule ExNtfy.ConfigTest do
  use ExUnit.Case, async: true

  alias ExNtfy.Config

  doctest ExNtfy.Config

  describe "resolve/2 defaults" do
    test "fills documented defaults when nothing is configured" do
      resolved = Config.resolve([], [])

      assert resolved[:base_url] == "https://ntfy.sh"
      assert resolved[:auth] == nil
      assert resolved[:auth_via] == :header
      assert resolved[:req_options] == []
    end

    test "omits receive_timeout and retry unless provided" do
      resolved = Config.resolve([], [])

      refute Keyword.has_key?(resolved, :receive_timeout)
      refute Keyword.has_key?(resolved, :retry)
    end
  end

  describe "resolve/2 precedence" do
    test "app config overrides defaults" do
      resolved = Config.resolve([], base_url: "https://cfg.example")
      assert resolved[:base_url] == "https://cfg.example"
    end

    test "per-call opts override app config" do
      resolved =
        Config.resolve(
          [base_url: "http://opt.example", auth_via: :query],
          base_url: "https://cfg.example",
          auth_via: :header
        )

      assert resolved[:base_url] == "http://opt.example"
      assert resolved[:auth_via] == :query
    end

    test "unmentioned keys fall through the layers independently" do
      resolved =
        Config.resolve(
          [receive_timeout: 5_000],
          base_url: "https://cfg.example",
          auth: {:token, "tk_x"}
        )

      assert resolved[:base_url] == "https://cfg.example"
      assert resolved[:auth] == {:token, "tk_x"}
      assert resolved[:receive_timeout] == 5_000
    end
  end

  describe "resolve/2 validation" do
    test "accepts all auth shapes" do
      assert Config.resolve([auth: {:basic, "u", "p"}], [])[:auth] == {:basic, "u", "p"}
      assert Config.resolve([auth: {:token, "tk_x"}], [])[:auth] == {:token, "tk_x"}
      assert Config.resolve([auth: nil], [])[:auth] == nil
    end

    test "rejects malformed auth" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Config.resolve([auth: {:basic, "only-user"}], [])
      end

      assert_raise NimbleOptions.ValidationError, fn ->
        Config.resolve([auth: "tk_x"], [])
      end
    end

    test "rejects unknown auth_via" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Config.resolve([auth_via: :cookie], [])
      end
    end

    test "rejects unknown option keys" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Config.resolve([bogus: true], [])
      end
    end

    test "ignores unknown keys in app config so unrelated env entries don't break clients" do
      resolved = Config.resolve([], unrelated_setting: :whatever)
      assert resolved[:base_url] == "https://ntfy.sh"
    end
  end
end
