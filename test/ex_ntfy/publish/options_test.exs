defmodule ExNtfy.Publish.OptionsTest do
  use ExUnit.Case, async: true

  alias ExNtfy.Action
  alias ExNtfy.Publish.Options

  doctest ExNtfy.Publish.Options

  describe "to_json_body/2" do
    test "always includes the topic" do
      assert {%{"topic" => "alerts"}, []} = Options.to_json_body("alerts", [])
    end

    test "message and plain string fields pass through" do
      {body, []} =
        Options.to_json_body("alerts",
          message: "hi",
          title: "Backup",
          click: "https://example.com",
          icon: "https://example.com/i.png",
          attach: "https://example.com/f.log",
          filename: "f.log",
          sequence_id: "seq-1"
        )

      assert body == %{
               "topic" => "alerts",
               "message" => "hi",
               "title" => "Backup",
               "click" => "https://example.com",
               "icon" => "https://example.com/i.png",
               "attach" => "https://example.com/f.log",
               "filename" => "f.log",
               "sequence_id" => "seq-1"
             }
    end

    test "markdown stays a JSON boolean" do
      assert {%{"markdown" => true}, []} = Options.to_json_body("t", markdown: true)
      assert {%{"markdown" => false}, []} = Options.to_json_body("t", markdown: false)
    end

    test "priority atoms map to their integers" do
      for {atom, int} <- [min: 1, low: 2, default: 3, high: 4, max: 5, urgent: 5] do
        assert {%{"priority" => ^int}, []} = Options.to_json_body("t", priority: atom)
      end
    end

    test "integer priorities 1-5 pass through" do
      for int <- 1..5 do
        assert {%{"priority" => ^int}, []} = Options.to_json_body("t", priority: int)
      end
    end

    test "priority 6 is rejected" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Options.to_json_body("t", priority: 6)
      end
    end

    test "priority 0 is rejected" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Options.to_json_body("t", priority: 0)
      end
    end

    test "an unknown priority atom is rejected" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Options.to_json_body("t", priority: :bogus)
      end
    end

    test "tags mix atoms and strings, preserving order" do
      assert {%{"tags" => ["tada", "deploy", "warning"]}, []} =
               Options.to_json_body("t", tags: [:tada, "deploy", :warning])
    end

    test "delay accepts a DateTime and encodes its unix timestamp" do
      assert {%{"delay" => "1783252800"}, []} =
               Options.to_json_body("t", delay: ~U[2026-07-05 12:00:00Z])
    end

    test "delay accepts a non-negative integer unix timestamp" do
      assert {%{"delay" => "1735920000"}, []} = Options.to_json_body("t", delay: 1_735_920_000)
    end

    test "delay strings pass through untouched" do
      for delay <- ["30m", "tomorrow, 3pm", "10am"] do
        assert {%{"delay" => ^delay}, []} = Options.to_json_body("t", delay: delay)
      end
    end

    test "a negative integer delay is rejected" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Options.to_json_body("t", delay: -5)
      end
    end

    test "email: true becomes \"yes\"; an address passes through" do
      assert {%{"email" => "yes"}, []} = Options.to_json_body("t", email: true)

      assert {%{"email" => "ops@example.com"}, []} =
               Options.to_json_body("t", email: "ops@example.com")
    end

    test "call: true becomes \"yes\"; a number passes through" do
      assert {%{"call" => "yes"}, []} = Options.to_json_body("t", call: true)
      assert {%{"call" => "+12223334444"}, []} = Options.to_json_body("t", call: "+12223334444")
    end

    test "actions encode structs and pass ntfy-shaped maps through" do
      actions = [
        %Action{type: :view, label: "Open", url: "https://example.com", clear: true},
        %{"action" => "copy", "label" => "Copy", "value" => "abc"}
      ]

      assert {%{"actions" => encoded}, []} = Options.to_json_body("t", actions: actions)

      assert encoded == [
               %{
                 "action" => "view",
                 "label" => "Open",
                 "url" => "https://example.com",
                 "clear" => true
               },
               %{"action" => "copy", "label" => "Copy", "value" => "abc"}
             ]
    end

    test "a raw JSON actions string is decoded into the body" do
      json = ~s([{"action":"view","label":"Open","url":"https://example.com"}])

      assert {%{"actions" => [%{"action" => "view"}]}, []} =
               Options.to_json_body("t", actions: json)
    end

    test "more than 3 actions are rejected" do
      actions =
        for i <- 1..4 do
          %Action{type: :view, label: "A#{i}", url: "https://example.com/#{i}"}
        end

      assert_raise NimbleOptions.ValidationError, fn ->
        Options.to_json_body("t", actions: actions)
      end
    end

    test "header-only options come back as headers, not JSON fields" do
      {body, headers} =
        Options.to_json_body("t",
          cache: false,
          firebase: false,
          unified_push: true,
          template: :github,
          poll_id: "p1"
        )

      assert body == %{"topic" => "t"}

      assert headers == [
               {"x-cache", "no"},
               {"x-firebase", "no"},
               {"x-unifiedpush", "1"},
               {"x-template", "github"},
               {"x-poll-id", "p1"}
             ]
    end

    test "default-valued booleans emit no header" do
      assert {%{"topic" => "t"}, []} =
               Options.to_json_body("t", cache: true, firebase: true, unified_push: false)
    end

    test "unknown options are rejected loudly" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Options.to_json_body("t", titel: "typo")
      end
    end
  end

  describe "to_headers/1" do
    test "maps every option to its canonical X- header" do
      headers =
        Options.to_headers(
          message: "hi",
          title: "Backup",
          priority: :urgent,
          tags: [:warning, "backup"],
          delay: 1_735_920_000,
          actions: [%Action{type: :copy, label: "Copy", value: "abc"}],
          click: "https://example.com",
          attach: "https://example.com/f.log",
          markdown: true,
          icon: "https://example.com/i.png",
          filename: "f.log",
          email: true,
          call: "+12223334444",
          sequence_id: "seq-1",
          cache: false,
          firebase: false,
          unified_push: true,
          template: true,
          poll_id: "p1"
        )

      assert headers == [
               {"x-message", "hi"},
               {"x-title", "Backup"},
               {"x-priority", "5"},
               {"x-tags", "warning,backup"},
               {"x-delay", "1735920000"},
               {"x-actions", "action=copy, label=Copy, value=abc"},
               {"x-click", "https://example.com"},
               {"x-attach", "https://example.com/f.log"},
               {"x-markdown", "yes"},
               {"x-icon", "https://example.com/i.png"},
               {"x-filename", "f.log"},
               {"x-email", "yes"},
               {"x-call", "+12223334444"},
               {"x-sequence-id", "seq-1"},
               {"x-cache", "no"},
               {"x-firebase", "no"},
               {"x-unifiedpush", "1"},
               {"x-template", "yes"},
               {"x-poll-id", "p1"}
             ]
    end

    test "markdown: false and default booleans emit no header" do
      assert Options.to_headers(markdown: false, cache: true, firebase: true) == []
    end

    test "non-ASCII header values are RFC 2047 B-encoded" do
      assert Options.to_headers(title: "Grüße 👋") ==
               [{"x-title", "=?UTF-8?B?R3LDvMOfZSDwn5GL?="}]
    end

    test "a raw JSON actions string passes through untouched" do
      json = ~s([{"action":"view","label":"Open","url":"https://example.com"}])
      assert Options.to_headers(actions: json) == [{"x-actions", json}]
    end

    test "multiple actions join with a semicolon" do
      actions = [
        %Action{type: :view, label: "Open", url: "https://example.com"},
        %Action{type: :copy, label: "Copy", value: "abc"}
      ]

      assert Options.to_headers(actions: actions) == [
               {"x-actions",
                "action=view, label=Open, url=https://example.com; " <>
                  "action=copy, label=Copy, value=abc"}
             ]
    end

    test "template variants encode to their header value" do
      assert Options.to_headers(template: true) == [{"x-template", "yes"}]
      assert Options.to_headers(template: :grafana) == [{"x-template", "grafana"}]
      assert Options.to_headers(template: :alertmanager) == [{"x-template", "alertmanager"}]
      assert Options.to_headers(template: "mycustom") == [{"x-template", "mycustom"}]
    end

    test "an invalid template value is rejected" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Options.to_headers(template: :slack)
      end
    end
  end

  describe "to_query/1" do
    test "maps options to their query parameter names" do
      query =
        Options.to_query(
          message: "hi",
          title: "Backup",
          priority: 5,
          tags: [:a, "b"],
          delay: "30m",
          markdown: true,
          email: true,
          sequence_id: "seq-1",
          cache: false,
          firebase: false,
          unified_push: true,
          template: :github,
          poll_id: "p1"
        )

      assert query == [
               message: "hi",
               title: "Backup",
               priority: "5",
               tags: "a,b",
               delay: "30m",
               markdown: "yes",
               email: "yes",
               sid: "seq-1",
               cache: "no",
               firebase: "no",
               up: "1",
               template: "github",
               "poll-id": "p1"
             ]
    end

    test "query values are not RFC 2047-encoded (URL encoding covers UTF-8)" do
      assert Options.to_query(title: "Grüße 👋") == [title: "Grüße 👋"]
    end

    test "actions encode to short format in the query string" do
      assert Options.to_query(actions: [%Action{type: :copy, label: "Copy", value: "abc"}]) ==
               [actions: "action=copy, label=Copy, value=abc"]
    end
  end

  describe "rfc2047_encode/1" do
    test "ASCII passes through untouched" do
      assert Options.rfc2047_encode("Backup done, all good; really") ==
               "Backup done, all good; really"
    end

    test "UTF-8 gets the =?UTF-8?B?...?= form" do
      assert Options.rfc2047_encode("Grüße 👋") == "=?UTF-8?B?R3LDvMOfZSDwn5GL?="
    end
  end
end
