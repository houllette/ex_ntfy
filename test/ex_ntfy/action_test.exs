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

  describe "to_json_map/1" do
    test "round-trips every fixture action exactly" do
      for map <- [
            Fixtures.view_action_map(),
            Fixtures.broadcast_action_map(),
            Fixtures.http_action_map(),
            Fixtures.copy_action_map()
          ] do
        assert map |> Action.from_map() |> Action.to_json_map() == map
      end
    end

    test "omits nil fields and a false clear" do
      assert Action.to_json_map(%Action{type: :copy, label: "Copy", value: "abc"}) ==
               %{"action" => "copy", "label" => "Copy", "value" => "abc"}
    end

    test "keeps clear when true" do
      assert %{"clear" => true} =
               Action.to_json_map(%Action{type: :view, label: "L", url: "u", clear: true})
    end

    test "encodes an unknown type by its string" do
      assert %{"action" => "teleport"} =
               Action.to_json_map(%Action{type: {:unknown, "teleport"}, label: "L"})
    end

    test "passes a plain ntfy-shaped map through untouched" do
      map = %{"action" => "view", "label" => "Open", "url" => "https://example.com"}
      assert Action.to_json_map(map) == map
    end
  end

  describe "to_short/1" do
    test "encodes a view action" do
      assert Action.to_short(Action.from_map(Fixtures.view_action_map())) ==
               "action=view, label=Open portal, url=https://example.com/deploys/42, clear=true"
    end

    test "encodes a broadcast action, flattening extras with sorted keys" do
      assert Action.to_short(Action.from_map(Fixtures.broadcast_action_map())) ==
               "action=broadcast, label=Take picture, intent=io.heckel.ntfy.USER_ACTION, " <>
                 "extras.camera=front, extras.cmd=pic"
    end

    test "encodes an http action, flattening headers and quoting the body" do
      assert Action.to_short(Action.from_map(Fixtures.http_action_map())) ==
               "action=http, label=Close door, url=https://api.example.com/door, " <>
                 ~s|method=PUT, headers.Authorization=Bearer zAzsx1sk.., | <>
                 ~s|body='{"action":"close"}'|
    end

    test "encodes a copy action" do
      assert Action.to_short(Action.from_map(Fixtures.copy_action_map())) ==
               "action=copy, label=Copy code, value=abc123"
    end

    test "double-quotes values containing commas or semicolons" do
      assert Action.to_short(%Action{type: :copy, label: "Deploy, now", value: "a;b"}) ==
               ~s(action=copy, label="Deploy, now", value="a;b")
    end

    test "single-quotes values containing double quotes" do
      assert Action.to_short(%Action{type: :copy, label: "Copy", value: ~s(say "hi")}) ==
               ~s(action=copy, label=Copy, value='say "hi"')
    end

    test "encodes an ntfy-shaped map via from_map" do
      assert Action.to_short(Fixtures.copy_action_map()) ==
               "action=copy, label=Copy code, value=abc123"
    end

    test "omits clear when false and encodes unknown types" do
      assert Action.to_short(%Action{type: {:unknown, "teleport"}, label: "Go"}) ==
               "action=teleport, label=Go"
    end
  end
end
