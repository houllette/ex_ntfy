defmodule ExNtfy.ErrorTest do
  use ExUnit.Case, async: true

  alias ExNtfy.{Error, Fixtures}

  describe "from_response/2" do
    test "parses an ntfy JSON error body given as a decoded map" do
      error = Error.from_response(429, Fixtures.error_429_map())

      assert %Error{
               code: 42_901,
               http: 429,
               error: "limit reached: too many requests, please be nice",
               link: "https://ntfy.sh/docs/publish/#limitations",
               reason: nil
             } = error
    end

    test "parses an ntfy JSON error body given as a raw binary" do
      error = Error.from_response(429, JSON.encode!(Fixtures.error_429_map()))

      assert %Error{code: 42_901, http: 429} = error
      assert error.error =~ "limit reached"
    end

    test "tolerates a plain-text body" do
      error = Error.from_response(502, "Bad Gateway")

      assert %Error{code: nil, http: 502, error: "Bad Gateway", link: nil} = error
    end

    test "tolerates an empty body" do
      error = Error.from_response(500, "")

      assert %Error{code: nil, http: 500, error: nil, link: nil} = error
    end

    test "tolerates a nil body" do
      assert %Error{code: nil, http: 500, error: nil, link: nil} = Error.from_response(500, nil)
    end

    test "tolerates a struct body (e.g. an unconsumed Req.Response.Async)" do
      error = Error.from_response(403, struct(Req.Response.Async))

      assert %Error{code: nil, http: 403, error: nil, link: nil} = error
    end

    test "falls back to the HTTP status when the JSON body lacks one" do
      error = Error.from_response(400, %{"code" => 40_001, "error" => "bad request"})

      assert %Error{code: 40_001, http: 400, error: "bad request"} = error
    end
  end

  describe "from_exception/1" do
    test "wraps a transport error" do
      transport = %Req.TransportError{reason: :timeout}
      assert %Error{reason: ^transport, http: nil, code: nil} = Error.from_exception(transport)
    end
  end

  describe "message/1 (raisable)" do
    test "renders the ntfy error fields" do
      rendered = Error.from_response(429, Fixtures.error_429_map()) |> Exception.message()

      assert rendered =~ "42901"
      assert rendered =~ "429"
      assert rendered =~ "limit reached"
      assert rendered =~ "https://ntfy.sh/docs/publish/#limitations"
    end

    test "renders a transport error reason" do
      rendered =
        Error.from_exception(%Req.TransportError{reason: :timeout})
        |> Exception.message()

      assert rendered =~ "timeout"
    end

    test "renders a bare HTTP status" do
      rendered = Error.from_response(500, "") |> Exception.message()
      assert rendered =~ "500"
    end

    test "renders a non-exception reason by inspecting it" do
      rendered =
        Exception.message(%Error{reason: {:invalid_response, {:missing_fields, ["id"]}}})

      assert rendered =~ "invalid_response"
      assert rendered =~ "missing_fields"
    end
  end
end
