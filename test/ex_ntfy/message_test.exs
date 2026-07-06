defmodule ExNtfy.MessageTest do
  use ExUnit.Case, async: true

  alias ExNtfy.{Action, Attachment, Fixtures, Message}

  doctest ExNtfy.Message

  describe "from_map/1 with a full-featured message" do
    test "parses every documented field" do
      map = Fixtures.full_message_map()

      assert {:ok, %Message{} = msg} = Message.from_map(map)
      assert msg.id == "sPs71M8A2T"
      assert msg.time == 1_735_920_000
      assert msg.event == :message
      assert msg.topic == "mytopic"
      assert msg.expires == 1_735_963_200
      assert msg.sequence_id == "deploy-42"
      assert msg.message == "Deploy finished **successfully**"
      assert msg.title == "Deploy status"
      assert msg.tags == ["tada", "deploy"]
      assert msg.priority == 4
      assert msg.click == "https://example.com/deploys/42"
      assert msg.icon == "https://example.com/icon.png"
      assert msg.content_type == "text/markdown"

      assert [%Action{}, %Action{}, %Action{}, %Action{}] = msg.actions

      assert %Attachment{
               name: "flower.jpg",
               url: "https://ntfy.sh/file/oaFAdEY1KC.jpg",
               type: "image/jpeg",
               size: 12_345,
               expires: 1_735_963_200
             } = msg.attachment
    end

    test "priority stays an integer 1-5, untranslated" do
      for priority <- 1..5 do
        map = Map.put(Fixtures.keepalive_map(), "priority", priority)
        assert {:ok, %Message{priority: ^priority}} = Message.from_map(map)
      end
    end

    test "raw retains the original decoded map" do
      map = Fixtures.full_message_map()
      assert {:ok, %Message{raw: ^map}} = Message.from_map(map)
    end
  end

  describe "from_map/1 with minimal events" do
    test "parses a keepalive event, leaving optional fields nil" do
      assert {:ok, %Message{} = msg} = Message.from_map(Fixtures.keepalive_map())
      assert msg.event == :keepalive
      assert msg.id == "F2ZoyEBBg9"
      assert msg.topic == "mytopic"

      for field <- [
            :message,
            :title,
            :tags,
            :priority,
            :click,
            :actions,
            :attachment,
            :expires,
            :sequence_id,
            :icon,
            :content_type
          ] do
        assert Map.fetch!(msg, field) == nil,
               "expected #{field} to be nil"
      end
    end

    test "parses an open event with a comma-separated topic list" do
      assert {:ok, %Message{event: :open, topic: "topic1,topic2"}} =
               Message.from_map(Fixtures.open_map())
    end

    test "parses all known event names to atoms" do
      known = %{
        "open" => :open,
        "keepalive" => :keepalive,
        "message" => :message,
        "message_clear" => :message_clear,
        "message_delete" => :message_delete,
        "poll_request" => :poll_request
      }

      for {name, atom} <- known do
        map = Map.put(Fixtures.keepalive_map(), "event", name)
        assert {:ok, %Message{event: ^atom}} = Message.from_map(map)
      end
    end
  end

  describe "from_map/1 leniency" do
    test "unknown event value becomes {:unknown, string} without crashing" do
      map = Map.put(Fixtures.keepalive_map(), "event", "subscription_update")

      assert {:ok, %Message{event: {:unknown, "subscription_update"}}} =
               Message.from_map(map)
    end

    test "unknown extra fields don't crash and are preserved in raw" do
      map =
        Fixtures.keepalive_map()
        |> Map.put("brand_new_field", "surprise")
        |> Map.put("nested", %{"a" => 1})

      assert {:ok, %Message{raw: raw}} = Message.from_map(map)
      assert raw["brand_new_field"] == "surprise"
      assert raw["nested"] == %{"a" => 1}
    end

    test "returns an error when always-present fields are missing" do
      map = Map.drop(Fixtures.keepalive_map(), ["id", "topic"])
      assert {:error, {:missing_fields, missing}} = Message.from_map(map)
      assert Enum.sort(missing) == ["id", "topic"]
    end
  end

  describe "from_json/1" do
    test "decodes NDJSON lines into messages" do
      json = JSON.encode!(Fixtures.full_message_map())

      assert {:ok, %Message{id: "sPs71M8A2T", event: :message}} = Message.from_json(json)
    end

    test "returns an error on invalid JSON" do
      assert {:error, _reason} = Message.from_json("not json {")
    end

    test "returns an error on JSON that is not an object" do
      assert {:error, _reason} = Message.from_json("[1, 2, 3]")
    end
  end
end
