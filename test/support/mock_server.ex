defmodule MockServer do
  @moduledoc """
  Helper module for creating mock HTTP servers in tests using Bypass.

  ## Usage

      defmodule MyIntegrationTest do
        use TestCase

        setup do
          bypass = MockServer.setup()
          {:ok, bypass: bypass}
        end

        test "makes API call", %{bypass: bypass} do
          MockServer.expect_get(bypass, "/users/1", 200, %{id: 1, name: "Test"})

          # Make actual HTTP request to bypass.port
          # ...
        end
      end
  """

  @doc """
  Sets up a new Bypass server for testing.

  Returns a Bypass struct that can be used to configure expectations.
  """
  def setup do
    Bypass.open()
  end

  @doc """
  Expects a GET request to the given path.

  ## Examples

      iex> MockServer.expect_get(bypass, "/users", 200, [%{id: 1}])
  """
  def expect_get(bypass, path, status \\ 200, response_body \\ %{}) do
    Bypass.expect_once(bypass, "GET", path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(status, Jason.encode!(response_body))
    end)
  end

  @doc """
  Expects a POST request to the given path.

  ## Examples

      iex> MockServer.expect_post(bypass, "/users", 201, %{id: 1})
  """
  def expect_post(bypass, path, status \\ 201, response_body \\ %{}) do
    Bypass.expect_once(bypass, "POST", path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(status, Jason.encode!(response_body))
    end)
  end

  @doc """
  Expects a PUT request to the given path.

  ## Examples

      iex> MockServer.expect_put(bypass, "/users/1", 200, %{id: 1})
  """
  def expect_put(bypass, path, status \\ 200, response_body \\ %{}) do
    Bypass.expect_once(bypass, "PUT", path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(status, Jason.encode!(response_body))
    end)
  end

  @doc """
  Expects a DELETE request to the given path.

  ## Examples

      iex> MockServer.expect_delete(bypass, "/users/1", 204)
  """
  def expect_delete(bypass, path, status \\ 204, response_body \\ "") do
    Bypass.expect_once(bypass, "DELETE", path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(status, if(response_body == "", do: "", else: Jason.encode!(response_body)))
    end)
  end

  @doc """
  Expects any request to return an error status.

  ## Examples

      iex> MockServer.expect_error(bypass, 500)
  """
  def expect_error(bypass, status \\ 500) do
    Bypass.expect(bypass, fn conn ->
      Plug.Conn.resp(conn, status, "")
    end)
  end

  @doc """
  Returns the URL for the Bypass server.

  ## Examples

      iex> MockServer.url(bypass)
      "http://localhost:12345"
  """
  def url(bypass) do
    "http://localhost:#{bypass.port}"
  end

  @doc """
  Returns the URL with a path for the Bypass server.

  ## Examples

      iex> MockServer.url(bypass, "/users")
      "http://localhost:12345/users"
  """
  def url(bypass, path) do
    "#{url(bypass)}#{path}"
  end
end
