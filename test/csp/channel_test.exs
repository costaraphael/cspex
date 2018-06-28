defmodule CSP.ChannelTest do
  use ExUnit.Case

  alias CSP.Channel

  doctest Channel

  test "the sliding buffer discards older values" do
    channel =
      1..10
      |> Enum.into(Channel.new(buffer_size: 5, buffer_type: :sliding))

    Channel.close(channel)

    assert Enum.to_list(channel) == [6, 7, 8, 9, 10]
  end

  test "the dropping buffer discards new values" do
    channel =
      1..10
      |> Enum.into(Channel.new(buffer_size: 5, buffer_type: :dropping))

    Channel.close(channel)

    assert Enum.to_list(channel) == [1, 2, 3, 4, 5]
  end

  test "the blocking buffer blocks writes" do
    channel = Channel.new()
    main = self()

    pid =
      spawn(fn ->
        Channel.put(channel, :foo)
        Channel.put(channel, :bar)
        send(main, {self(), :done})
      end)

    refute_receive {^pid, :done}
    assert Channel.get(channel) == :foo

    refute_receive {^pid, :done}
    assert Channel.get(channel) == :bar

    assert_receive {^pid, :done}
  end

  test "putting in a closed channel raises" do
    channel = Channel.new()

    Channel.close(channel)

    assert {:error, :closed} = Channel.put(channel, :value)
  end

  test "putting nil in a channel raises" do
    channel = Channel.new()

    assert_raise(ArgumentError, ~r/Can't put nil on a channel./, fn ->
      Channel.put(channel, nil)
    end)
  end

  test "a channel does not get values from dead processes" do
    channel = Channel.new()

    func = fn ->
      Channel.put(channel, self())
    end

    pid1 = spawn_link(func)
    Process.sleep(10)
    pid2 = spawn_link(func)

    Process.flag(:trap_exit, true)
    Process.exit(pid1, :kill)
    Process.sleep(10)

    assert pid2 == Channel.get(channel)
  end

  test "a channel does not send values to dead processes" do
    channel = Channel.new()
    main = self()

    func = fn ->
      send(main, {self(), Channel.get(channel)})
    end

    pid1 = spawn_link(func)
    Process.sleep(10)
    pid2 = spawn_link(func)

    Process.flag(:trap_exit, true)
    Process.exit(pid1, :kill)
    Process.sleep(10)

    assert :ok = Channel.put(channel, :foo)

    assert_receive {^pid2, :foo}
  end

  test "Enumerable and Colectable protocols work as they should" do
    channel = Enum.into(1..5, Channel.new(buffer_size: 5))

    Channel.close(channel)

    other_channel =
      for x <- channel, into: Channel.new(buffer_size: 5) do
        x * 2
      end

    Channel.close(other_channel)

    assert Enum.to_list(other_channel) == [2, 4, 6, 8, 10]
    assert Enum.to_list(channel) == []
  end
end
