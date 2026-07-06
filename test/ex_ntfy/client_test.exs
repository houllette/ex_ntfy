defmodule ExNtfy.ClientTest do
  use ExUnit.Case, async: true

  import ExNtfy.TestHelpers

  alias ExNtfy.{Client, Error, Fixtures}

  @user_agent "ex_ntfy/#{Mix.Project.config()[:version]} (Elixir)"

  defp echo_conn(fun) do
    req_stub(fn conn ->
      fun.(conn)
      Req.Test.json(conn, %{})
    end)
  end

  describe "new/1 base_url" do
    test "defaults to https://ntfy.sh" do
      opts = echo_conn(fn conn -> assert conn.host == "ntfy.sh" end)

      assert {:ok, _} = Client.request(opts, url: "/mytopic", method: :get)
    end

    test "base_url option overrides the default" do
      opts = echo_conn(fn conn -> assert conn.host == "ntfy.example.com" end)

      assert {:ok, _} =
               Client.request([base_url: "https://ntfy.example.com"] ++ opts,
                 url: "/mytopic",
                 method: :get
               )
    end
  end

  describe "new/1 authentication" do
    test "{:basic, user, pass} sets a Basic Authorization header" do
      opts =
        echo_conn(fn conn ->
          assert Plug.Conn.get_req_header(conn, "authorization") ==
                   ["Basic dGVzdHVzZXI6ZmFrZXBhc3N3b3Jk"]
        end)

      assert {:ok, _} =
               Client.request([auth: {:basic, "testuser", "fakepassword"}] ++ opts,
                 url: "/mytopic",
                 method: :get
               )
    end

    test "{:token, token} sets a Bearer Authorization header" do
      opts =
        echo_conn(fn conn ->
          assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer tk_mytoken"]
        end)

      assert {:ok, _} =
               Client.request([auth: {:token, "tk_mytoken"}] ++ opts,
                 url: "/mytopic",
                 method: :get
               )
    end

    test "auth_via: :query sets ?auth= to unpadded base64url of the full header value" do
      opts =
        echo_conn(fn conn ->
          assert Plug.Conn.get_req_header(conn, "authorization") == []

          conn = Plug.Conn.fetch_query_params(conn)

          assert conn.query_params["auth"] ==
                   "QmFzaWMgZEdWemRIVnpaWEk2Wm1GclpYQmhjM04zYjNKaw"
        end)

      assert {:ok, _} =
               Client.request(
                 [auth: {:basic, "testuser", "fakepassword"}, auth_via: :query] ++ opts,
                 url: "/mytopic",
                 method: :get
               )
    end

    test "auth_via: :query works for tokens too" do
      opts =
        echo_conn(fn conn ->
          conn = Plug.Conn.fetch_query_params(conn)
          assert conn.query_params["auth"] == "QmVhcmVyIHRrX215dG9rZW4"
        end)

      assert {:ok, _} =
               Client.request([auth: {:token, "tk_mytoken"}, auth_via: :query] ++ opts,
                 url: "/mytopic",
                 method: :get
               )
    end

    test "no auth means no Authorization header and no ?auth param" do
      opts =
        echo_conn(fn conn ->
          assert Plug.Conn.get_req_header(conn, "authorization") == []

          conn = Plug.Conn.fetch_query_params(conn)
          refute Map.has_key?(conn.query_params, "auth")
        end)

      assert {:ok, _} = Client.request(opts, url: "/mytopic", method: :get)
    end
  end

  describe "new/1 req_options and headers" do
    test "sends the ex_ntfy user-agent by default" do
      opts =
        echo_conn(fn conn ->
          assert Plug.Conn.get_req_header(conn, "user-agent") == [@user_agent]
        end)

      assert {:ok, _} = Client.request(opts, url: "/mytopic", method: :get)
    end

    test "req_options merge wins over computed defaults" do
      opts =
        echo_conn(fn conn ->
          assert conn.host == "override.example.com"
          assert Plug.Conn.get_req_header(conn, "user-agent") == ["custom-agent/1.0"]
        end)

      [req_options: req_options] = opts

      merged_opts = [
        base_url: "https://loses.example.com",
        req_options:
          req_options ++
            [
              base_url: "https://override.example.com",
              headers: [user_agent: "custom-agent/1.0"]
            ]
      ]

      assert {:ok, _} = Client.request(merged_opts, url: "/mytopic", method: :get)
    end

    test "extra headers via req_options keep the default user-agent" do
      opts =
        echo_conn(fn conn ->
          assert Plug.Conn.get_req_header(conn, "user-agent") == [@user_agent]
          assert Plug.Conn.get_req_header(conn, "x-custom") == ["yes"]
        end)

      [req_options: req_options] = opts

      merged_opts = [req_options: req_options ++ [headers: [x_custom: "yes"]]]

      assert {:ok, _} = Client.request(merged_opts, url: "/mytopic", method: :get)
    end
  end

  describe "request/2" do
    test "accepts a prebuilt Req.Request" do
      opts = echo_conn(fn conn -> assert conn.host == "ntfy.sh" end)

      req = Client.new(opts)

      assert {:ok, %Req.Response{status: 200}} =
               Client.request(req, url: "/mytopic", method: :get)
    end

    test "maps non-2xx responses to ExNtfy.Error" do
      opts =
        req_stub(fn conn ->
          conn
          |> Plug.Conn.put_status(429)
          |> Req.Test.json(Fixtures.error_429_map())
        end)

      assert {:error, %Error{code: 42_901, http: 429}} =
               Client.request(opts, url: "/mytopic", method: :post, body: "hi")
    end

    test "maps transport errors to ExNtfy.Error" do
      opts = req_stub(fn conn -> Req.Test.transport_error(conn, :timeout) end)

      assert {:error, %Error{reason: %Req.TransportError{reason: :timeout}}} =
               Client.request([retry: false] ++ opts, url: "/mytopic", method: :get)
    end
  end
end
