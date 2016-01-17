defmodule CSP.ChannelTest do
  use ExUnit.Case
  use CSP

  doctest CSP.Channel

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

  test "putting in a closed channel raises" do
    channel = Channel.new

    Channel.close(channel)

    assert_raise(RuntimeError, ~r/Can't put a new value on a closed channel./, fn ->
      Channel.put(channel, :value)
    end)
  end

  test "putting nil in a channel raises" do
    channel = Channel.new

    assert_raise(RuntimeError, ~r/Can't put nil on a channel./, fn ->
      Channel.put(channel, nil)
    end)
  end

  test "Enumerable and Colectable protocols work as they should" do
    channel = Enum.into(1..5, Channel.new(buffer_size: 5))

    Channel.close(channel)

    other_channel = for x <- channel, into: Channel.new(buffer_size: 5) do
      x * 2
    end

    Channel.close(other_channel)

    assert Enum.to_list(other_channel) == [2, 4, 6, 8, 10]
    assert Enum.to_list(channel) == []
  end
end
