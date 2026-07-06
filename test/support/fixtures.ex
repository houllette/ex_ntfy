defmodule Fixtures do
  @moduledoc """
  Test fixtures and factory functions for generating test data.

  ## Usage

      defmodule MyTest do
        use TestCase
        import Fixtures

        test "something with fixture data" do
          data = fixture(:user)
          # Use data in test
        end
      end
  """

  @doc """
  Generates fixture data based on the given type.

  ## Examples

      iex> Fixtures.fixture(:user)
      %{id: 1, name: "Test User", email: "test@example.com"}

      iex> Fixtures.fixture(:error_response)
      %{error: "Something went wrong", code: 500}
  """
  def fixture(type, attrs \\ %{})

  def fixture(:user, attrs) do
    %{
      id: 1,
      name: "Test User",
      email: "test@example.com",
      created_at: DateTime.utc_now()
    }
    |> Map.merge(attrs)
  end

  def fixture(:error_response, attrs) do
    %{
      error: "Something went wrong",
      code: 500,
      message: "Internal server error"
    }
    |> Map.merge(attrs)
  end

  def fixture(:validation_error, attrs) do
    %{
      error: "Validation failed",
      code: 422,
      errors: [
        %{field: "email", message: "is required"}
      ]
    }
    |> Map.merge(attrs)
  end

  def fixture(:not_found_error, attrs) do
    %{
      error: "Resource not found",
      code: 404,
      message: "The requested resource was not found"
    }
    |> Map.merge(attrs)
  end

  def fixture(:unauthorized_error, attrs) do
    %{
      error: "Unauthorized",
      code: 401,
      message: "Authentication required"
    }
    |> Map.merge(attrs)
  end

  @doc """
  Generates a list of fixtures.

  ## Examples

      iex> Fixtures.fixture_list(:user, 3)
      [%{id: 1, ...}, %{id: 2, ...}, %{id: 3, ...}]
  """
  def fixture_list(type, count, base_attrs \\ %{}) do
    Enum.map(1..count, fn i ->
      attrs = Map.put(base_attrs, :id, i)
      fixture(type, attrs)
    end)
  end

  @doc """
  Loads a fixture file from the fixtures directory.

  ## Examples

      iex> Fixtures.load_file("sample_response.json")
      {:ok, %{"data" => [...]}}
  """
  def load_file(filename) do
    path = Path.join([__DIR__, "../fixtures", filename])

    case File.read(path) do
      {:ok, content} ->
        case Path.extname(filename) do
          ".json" -> Jason.decode(content)
          _ -> {:ok, content}
        end

      error ->
        error
    end
  end
end
