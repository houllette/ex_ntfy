defmodule ExNtfy.ActionTest do
  use ExUnit.Case, async: true

  alias ExNtfy.{Action, Fixtures}

  describe "from_map/1" do
    test "parses a view action" do
      assert %Action{
               type: :view,
               id: "action-1",
               label: "Open portal",
               url: "https://example.com/deploys/42",
               clear: true
             } = Action.from_map(Fixtures.view_action_map())
    end

    test "parses a broadcast action with extras map" do
      assert %Action{
               type: :broadcast,
               label: "Take picture",
               intent: "io.heckel.ntfy.USER_ACTION",
               extras: %{"cmd" => "pic", "camera" => "front"}
             } = Action.from_map(Fixtures.broadcast_action_map())
    end

    test "parses an http action with method, headers and body" do
      assert %Action{
               type: :http,
               label: "Close door",
               url: "https://api.example.com/door",
               method: "PUT",
               headers: %{"Authorization" => "Bearer zAzsx1sk.."},
               body: ~s({"action":"close"})
             } = Action.from_map(Fixtures.http_action_map())
    end

    test "parses a copy action with value" do
      assert %Action{type: :copy, label: "Copy code", value: "abc123"} =
               Action.from_map(Fixtures.copy_action_map())
    end

    test "clear defaults to false when absent" do
      assert %Action{clear: false} = Action.from_map(Fixtures.copy_action_map())
    end

    test "a missing action type is nil" do
      assert %Action{type: nil} = Action.from_map(%{"label" => "??"})
    end

    test "unknown action type is kept as {:unknown, string}" do
      map = Map.put(Fixtures.view_action_map(), "action", "teleport")
      assert %Action{type: {:unknown, "teleport"}} = Action.from_map(map)
    end

    test "fields not applicable to the type are nil" do
      action = Action.from_map(Fixtures.view_action_map())
      assert action.method == nil
      assert action.headers == nil
      assert action.body == nil
      assert action.intent == nil
      assert action.extras == nil
      assert action.value == nil
    end
  end
end
