defmodule ExNtfy.Subscribe.OptionsTest do
  use ExUnit.Case, async: true

  alias ExNtfy.Subscribe.Options

  doctest ExNtfy.Subscribe.Options

  describe "path/2" do
    test "builds a single-topic json path" do
      assert Options.path("mytopic") == "/mytopic/json"
    end

    test "joins a topic list with commas" do
      assert Options.path(["topic1", "topic2", "topic3"]) == "/topic1,topic2,topic3/json"
    end

    test "a comma-separated string behaves like a list" do
      assert Options.path("topic1,topic2") == "/topic1,topic2/json"
    end

    test "escapes URL-meaningful characters per topic, keeping comma separators" do
      assert Options.path(["my topic", "other/one"]) == "/my%20topic,other%2Fone/json"
    end

    test "supports the other stream formats for Phase 6" do
      assert Options.path("t", :sse) == "/t/sse"
      assert Options.path("t", :raw) == "/t/raw"
      assert Options.path("t", :ws) == "/t/ws"
    end

    test "rejects an empty topic list" do
      assert_raise ArgumentError, fn -> Options.path([]) end
      assert_raise ArgumentError, fn -> Options.path("") end
    end
  end

  describe "to_query/1 — :since" do
    test "duration and message-id strings pass through verbatim" do
      assert Options.to_query(since: "10m") == [since: "10m"]
      assert Options.to_query(since: "xE73Iyuabi") == [since: "xE73Iyuabi"]
    end

    test "a unix timestamp integer encodes as a string" do
      assert Options.to_query(since: 1_735_920_000) == [since: "1735920000"]
    end

    test "a DateTime encodes as its unix timestamp" do
      assert Options.to_query(since: ~U[2026-07-05 12:00:00Z]) == [since: "1783252800"]
    end

    test ":all and :latest encode by name" do
      assert Options.to_query(since: :all) == [since: "all"]
      assert Options.to_query(since: :latest) == [since: "latest"]
    end

    test "a negative timestamp is rejected" do
      assert_raise NimbleOptions.ValidationError, fn -> Options.to_query(since: -1) end
    end

    test "an unknown atom is rejected" do
      assert_raise NimbleOptions.ValidationError, fn -> Options.to_query(since: :oldest) end
    end
  end

  describe "to_query/1 — other params" do
    test "scheduled: true → 1; false emits nothing" do
      assert Options.to_query(scheduled: true) == [scheduled: "1"]
      assert Options.to_query(scheduled: false) == []
    end

    test "id, message, and title pass through verbatim" do
      assert Options.to_query(id: "xE73Iyuabi", message: "exact body", title: "exact title") ==
               [id: "xE73Iyuabi", message: "exact body", title: "exact title"]
    end

    test "a priority list OR-filter comma-joins, mapping atoms" do
      assert Options.to_query(priority: [:high, 5]) == [priority: "4,5"]
      assert Options.to_query(priority: [1, :low]) == [priority: "1,2"]
    end

    test "a single priority works without a list" do
      assert Options.to_query(priority: :max) == [priority: "5"]
      assert Options.to_query(priority: 4) == [priority: "4"]
    end

    test "invalid priorities are rejected, also inside lists" do
      assert_raise NimbleOptions.ValidationError, fn -> Options.to_query(priority: 6) end

      assert_raise NimbleOptions.ValidationError, fn ->
        Options.to_query(priority: [4, :bogus])
      end

      assert_raise NimbleOptions.ValidationError, fn -> Options.to_query(priority: []) end
    end

    test "tags mix atoms and strings, comma-joined in order" do
      assert Options.to_query(tags: [:warning, "backup", :cd]) == [tags: "warning,backup,cd"]
    end

    test "unknown options are rejected loudly" do
      assert_raise NimbleOptions.ValidationError, fn -> Options.to_query(sched: true) end
    end

    test "params come out in a stable canonical order" do
      query =
        Options.to_query(
          tags: [:a],
          priority: 5,
          title: "T",
          message: "M",
          id: "I",
          scheduled: true,
          since: :all
        )

      assert query == [
               since: "all",
               scheduled: "1",
               id: "I",
               message: "M",
               title: "T",
               priority: "5",
               tags: "a"
             ]
    end
  end
end
