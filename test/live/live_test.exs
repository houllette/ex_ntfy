defmodule ExNtfy.LiveTest do
  @moduledoc """
  Opt-in integration tests against the real ntfy.sh — excluded by default,
  run with `mix test --only live`.

  Mindful of ntfy.sh limits (reference §1.8: ~60-request burst, 250/day):
  each test uses one random topic, the whole suite makes < 20 requests, and
  publishes are spaced out. Never enable in default CI.
  """

  use ExUnit.Case, async: false

  alias ExNtfy.{Action, Message}

  @moduletag :live
  @moduletag timeout: 120_000

  # Spacing between publishes, to stay friendly to the public instance.
  @pace_ms 500

  setup do
    suffix = Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)
    {:ok, topic: "ex-ntfy-ci-#{suffix}"}
  end

  test "publish: minimal and kitchen-sink round-trip", %{topic: topic} do
    assert {:ok, %Message{} = minimal} = ExNtfy.publish(topic, "minimal live message")
    assert is_binary(minimal.id)
    assert is_integer(minimal.time)
    assert minimal.event == :message
    assert minimal.topic == topic
    assert minimal.message == "minimal live message"

    Process.sleep(@pace_ms)

    assert {:ok, %Message{} = fancy} =
             ExNtfy.publish(topic, "kitchen-sink **live** message",
               title: "ex_ntfy live test",
               priority: :high,
               tags: [:test_tube, "ex-ntfy-ci"],
               click: "https://github.com/houllette/ex_ntfy",
               markdown: true,
               actions: [
                 %Action{
                   type: :view,
                   label: "Repo",
                   url: "https://github.com/houllette/ex_ntfy"
                 }
               ]
             )

    assert fancy.title == "ex_ntfy live test"
    assert fancy.priority == 4
    assert fancy.tags == ["test_tube", "ex-ntfy-ci"]
    assert fancy.click == "https://github.com/houllette/ex_ntfy"
    assert [%Action{type: :view, label: "Repo"}] = fancy.actions
  end

  test "poll: finds published messages and applies filters", %{topic: topic} do
    {:ok, low} = ExNtfy.publish(topic, "low one", priority: :low, tags: [:aaa])
    Process.sleep(@pace_ms)
    {:ok, high} = ExNtfy.publish(topic, "high one", priority: :urgent, tags: [:aaa, :bbb])

    # the server cache is eventually consistent — poll with patience
    messages = poll_until(topic, [since: :all], 2)
    ids = Enum.map(messages, & &1.id)
    assert low.id in ids
    assert high.id in ids

    # priority filter is OR semantics
    assert [only_high] = poll_until(topic, [since: :all, priority: [:high, :urgent]], 1)
    assert only_high.id == high.id

    # tags filter is AND semantics
    assert [tagged] = poll_until(topic, [since: :all, tags: [:aaa, :bbb]], 1)
    assert tagged.id == high.id

    assert [_first, _second] = poll_until(topic, [since: :all, tags: [:aaa]], 2)
  end

  # Polls repeatedly (1s apart, up to 8 tries) until at least `expected`
  # messages appear; returns whatever the final poll saw.
  defp poll_until(topic, opts, expected, attempts \\ 8) do
    {:ok, messages} = ExNtfy.poll(topic, opts)

    if length(messages) >= expected or attempts <= 1 do
      messages
    else
      Process.sleep(1_000)
      poll_until(topic, opts, expected, attempts - 1)
    end
  end

  test "subscribe: delivery plus update/clear/delete lifecycle", %{topic: topic} do
    {:ok, sub} = ExNtfy.subscribe(topic)
    assert_receive {:ntfy_lifecycle, ^sub, :connected}, 15_000

    {:ok, published} = ExNtfy.publish(topic, "streamed live message", title: "live")
    assert_receive {:ntfy, ^sub, %Message{} = received}, 15_000
    assert received.id == published.id
    assert received.message == "streamed live message"

    Process.sleep(@pace_ms)

    # update by reusing the returned id as the sequence id
    {:ok, updated} = ExNtfy.update(topic, published.id, "updated live message")
    assert_receive {:ntfy, ^sub, %Message{id: updated_id}}, 15_000
    assert updated_id == updated.id

    Process.sleep(@pace_ms)

    {:ok, cleared} = ExNtfy.clear(topic, published.id)
    assert cleared.event == :message_clear

    assert_receive {:ntfy_lifecycle, ^sub, {:message_clear, %Message{}}}, 15_000

    Process.sleep(@pace_ms)

    {:ok, deleted} = ExNtfy.delete(topic, published.id)
    assert deleted.event == :message_delete

    assert_receive {:ntfy_lifecycle, ^sub, {:message_delete, %Message{}}}, 15_000

    assert :ok = ExNtfy.unsubscribe(sub)
  end
end
