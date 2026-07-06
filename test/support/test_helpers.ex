defmodule ExNtfy.TestHelpers do
  @moduledoc """
  Shared helpers for ExNtfy tests.
  """

  @doc """
  Wires a `Req.Test` stub for the calling test and returns client options
  that route SDK HTTP calls through it, e.g. `ExNtfy.Client.new(req_stub(fun))`.
  """
  @spec req_stub((Plug.Conn.t() -> Plug.Conn.t())) :: keyword()
  def req_stub(fun) when is_function(fun, 1) do
    Req.Test.stub(ExNtfy, fun)
    [req_options: [plug: {Req.Test, ExNtfy}]]
  end
end
