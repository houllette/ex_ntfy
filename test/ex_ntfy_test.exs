defmodule ExNtfyTest do
  use ExUnit.Case, async: true

  doctest ExNtfy

  test "ExNtfy module exists" do
    assert Code.ensure_loaded?(ExNtfy)
  end
end
