defmodule CSP.Channel.Server do
  @moduledoc false

  @doc false
  def init(options) do
     {:ok, %{senders: [],
             receivers: [],
             buffer: [],
             options: options,
             closed: false}}
  end

  @doc false
  def handle_call({:put, _item}, _from, %{closed: true} = state) do
    {:reply, :error, state}
  end

  def handle_call({:put, item}, from, %{receivers: []} = state) do
    buffer_type = state.options[:buffer_type]
    buffer_size = state.options[:buffer_size]

    case put_in_buffer(state.buffer, item, buffer_type, buffer_size) do
      {:ok, buffer} ->
        {:reply, :ok, Map.put(state, :buffer, buffer)}

      {:error, :block} ->
        {:noreply, Map.update!(state, :senders, &[{from, item} | &1])}
    end
  end

  def handle_call({:put, item}, from, state) do
    case next_peer(state.receivers) do
      {nil, []} ->
        handle_call({:put, item}, from, Map.put(state, :receivers, []))
      {receiver, receivers} ->
        GenServer.reply(receiver, item)

        {:reply, :ok, Map.put(state, :receivers, receivers)}
    end
  end

  @doc false
  def handle_call(:get, from, %{buffer: [], senders: [], closed: false} = state) do
    {:noreply, Map.update!(state, :receivers, &[from | &1])}
  end

  def handle_call(:get, _from, %{buffer: [], senders: [], closed: true} = state) do
    {:reply, nil, state}
  end

  def handle_call(:get, from, %{buffer: []} = state) do
    case next_peer(state.senders) do
      {nil, []} ->
        handle_call(:get, from, Map.put(state, :senders, []))

      {{sender, item}, senders} ->
        GenServer.reply(sender, :ok)

        {:reply, item, Map.put(state, :senders, senders)}
    end
  end

  def handle_call(:get, _from, %{senders: []} = state) do
    {item, buffer} = pop(state.buffer)

    {:reply, item, Map.put(state, :buffer, buffer)}
  end

  def handle_call(:get, from, state) do
    case next_peer(state.senders) do
      {nil, []} ->
        handle_call(:get, from, Map.put(state, :senders, []))

      {{sender, to_buffer}, senders} ->
        {item, buffer} = pop(state.buffer)

        GenServer.reply(sender, :ok)
        buffer = [to_buffer | buffer]

        state = state
                |> Map.put(:buffer, buffer)
                |> Map.put(:senders, senders)

        {:reply, item, state}
    end
  end

  @doc false
  def handle_call(:close, _from, state) do
    Enum.each(state.receivers, &GenServer.reply(&1, nil))

    {:reply, :ok, Map.put(state, :closed, true)}
  end

  @doc false
  def handle_call(:size, _from, state) do
    {:reply, length(state.buffer) + length(state.senders), state}
  end

  @doc false
  def handle_call({:"member?", value}, _from, state) do
    items = Enum.map(state.senders, &elem(&1, 1)) ++ state.buffer

    {:reply, Enum.member?(items, value), state}
  end

  @doc false
  def handle_call(:"closed?", _from, state) do
    {:reply, state.closed, state}
  end

  defp next_peer(peers) do
    {next, peers} = peers |> Enum.reverse |> next_alive

    {next, Enum.reverse(peers)}
  end

  defp next_alive([]), do: {nil, []}
  defp next_alive([peer | peers]) do
    if peer |> extract_pid |> Process.alive? do
      {peer, peers}
    else
      next_alive(peers)
    end
  end

  defp extract_pid({{pid, _flag}, _value}), do: pid
  defp extract_pid({pid, _flag}), do: pid

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
