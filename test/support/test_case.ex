defmodule TestCase do
  @moduledoc """
  Base test case for SDK tests.

  Provides common setup and helpers for all tests.

  ## Usage

      defmodule MyApiTest do
        use TestCase

        test "something works" do
          # Test code here
        end
      end
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import TestCase
      import Mox

      # Setup Mox for concurrent tests
      setup :verify_on_exit!
    end
  end

  @doc """
  Creates a mock HTTP client for testing.

  ## Examples

      iex> client = TestCase.mock_client()
      %Tesla.Client{...}
  """
  def mock_client(opts \\ []) do
    adapter = Keyword.get(opts, :adapter, HTTPClientMock)
    Tesla.client([], adapter)
  end

  @doc """
  Expects a successful HTTP response.

  ## Examples

      iex> expect_success_response(200, %{data: "value"})
  """
  def expect_success_response(status \\ 200, body \\ %{}) do
    Mox.expect(HTTPClientMock, :call, fn env, _opts ->
      {:ok, %{env | status: status, body: body}}
    end)
  end

  @doc """
  Expects an HTTP error response.

  ## Examples

      iex> expect_error_response(404, %{error: "Not found"})
  """
  def expect_error_response(status, body \\ %{}) do
    Mox.expect(HTTPClientMock, :call, fn env, _opts ->
      {:ok, %{env | status: status, body: body}}
    end)
  end

  @doc """
  Expects a network error.

  ## Examples

      iex> expect_network_error(:timeout)
  """
  def expect_network_error(reason \\ :timeout) do
    Mox.expect(HTTPClientMock, :call, fn _env, _opts ->
      {:error, reason}
    end)
  end
end
