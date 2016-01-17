defmodule CSP.Channel.Server do
  @moduledoc false

  use ExActor.GenServer

  @doc false
  def init(options) do
     {:ok, %{senders:   [],
             receivers: [],
             buffer:    [],
             options:   options,
             closed: false}}
  end

  @doc false
  defhandlecall put(_item), state: %{closed: true} do
    reply(:error)
  end

  defhandlecall put(item), state: %{receivers: [], options: options, buffer: buffer} = state, from: from do
    case put_in_buffer(buffer, item, options[:buffer_type], options[:buffer_size]) do
      {:ok, buffer} ->
        set_and_reply(Map.put(state, :buffer, buffer), :ok)

      {:error, :block} ->
        new_state(Map.update!(state, :senders, &[{from, item} | &1]))
    end
  end

  defhandlecall put(item), state: %{receivers: receivers} = state do
    {receiver, receivers} = pop(receivers)
    GenServer.reply(receiver, item)

    set_and_reply(Map.put(state, :receivers, receivers), :ok)
  end

  @doc false
  defhandlecall get, state: %{buffer: [], senders: [], closed: false} = state, from: from do
    new_state(Map.update!(state, :receivers, &[from | &1]))
  end

  defhandlecall get, state: %{buffer: [], senders: [], closed: true} do
    reply(nil)
  end

  defhandlecall get, state: %{buffer: [], senders: senders} = state do
    {{sender, item}, senders} = pop(senders)
    GenServer.reply(sender, :ok)

    set_and_reply(Map.put(state, :senders, senders), item)
  end

  defhandlecall get, state: %{buffer: buffer, senders: []} = state do
    {item, buffer} = pop(buffer)

    set_and_reply(Map.put(state, :buffer, buffer), item)
  end

  defhandlecall get, state: %{buffer: buffer, senders: senders} = state do
    {item, buffer} = pop(buffer)
    {{sender, to_buffer}, senders} = pop(senders)

    GenServer.reply(sender, :ok)
    buffer = [to_buffer | buffer]

    state
    |> Map.put(:buffer, buffer)
    |> Map.put(:senders, senders)
    |> set_and_reply(item)
  end

  @doc false
  defhandlecall close, state: %{receivers: receivers} = state do
    Enum.each(receivers, &GenServer.reply(&1, nil))

    set_and_reply(Map.put(state, :closed, true), :ok)
  end

  @doc false
  defhandlecall size, state: %{buffer: buffer, senders: senders} do
    reply(length(buffer) + length(senders))
  end

  @doc false
  defhandlecall member?(value), state: %{buffer: buffer, senders: senders} do
    items = Enum.map(senders, &elem(&1, 1)) ++ buffer

    reply(Enum.member?(items, value))
  end

  @doc false
  defhandlecall closed?, state: %{closed: closed} do
    reply(closed)
  end

  defp pop(list) do
    item = List.last(list)

    {item, List.delete_at(list, -1)}
  end

  defp put_in_buffer(buffer, item, _type, size) when length(buffer) < size do
    {:ok, [item | buffer]}
  end

  defp put_in_buffer(_buffer, _item, :blocking, _size) do
    {:error, :block}
  end

  defp put_in_buffer(buffer, item, :sliding, _size) do
    {:ok, [item | List.delete_at(buffer, -1)]}
  end

  defp put_in_buffer(buffer, _item, :dropping, _size) do
    {:ok, buffer}
  end
end
