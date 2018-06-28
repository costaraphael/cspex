defmodule CSP.Channel.Server do
  @moduledoc false

  alias CSP.Buffer

  require Logger

  @behaviour GenServer

  @impl GenServer
  def init(buffer) do
    {:ok,
     %{
       senders: :queue.new(),
       receivers: :queue.new(),
       buffer: buffer,
       to_reply: [],
       closed: false
     }}
  end

  @impl GenServer
  def handle_call({:put, item}, {pid, _ref} = from, state) do
    if state.closed do
      {:reply, :closed, state}
    else
      ref = Process.monitor(pid)
      from = {from, ref}

      state
      |> Map.update!(:senders, &:queue.in({from, item}, &1))
      |> handle_state()
    end
  end

  @impl GenServer
  def handle_call(:get, {pid, _ref} = from, state) do
    ref = Process.monitor(pid)
    from = {from, ref}

    state
    |> Map.update!(:receivers, &:queue.in(from, &1))
    |> handle_state()
  end

  @impl GenServer
  def handle_call(:closed?, _from, state) do
    {:reply, state.closed, state}
  end

  @impl GenServer
  def handle_call(:close, {pid, _ref} = from, state) do
    sender_replies =
      state.senders
      |> :queue.to_list()
      |> Enum.map(&{&1, :closed})

    ref = Process.monitor(pid)
    to_reply = [{{from, ref}, :ok} | sender_replies]

    state
    |> Map.replace!(:closed, true)
    |> Map.replace!(:senders, :queue.new())
    |> Map.replace!(:to_reply, to_reply)
    |> handle_state()
  end

  @impl GenServer
  def handle_cast(request, state) do
    Logger.error("Invalid cast received: #{inspect(request)}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _, _}, state) do
    {:noreply, clear_dead_process(state, ref)}
  end

  @impl GenServer
  def handle_info(request, state) do
    Logger.error("Invalid message received: #{inspect(request)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, _state) do
    :ok
  end

  @impl GenServer
  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  defp handle_state(state) do
    new_state =
      state
      |> answer_receivers()
      |> update_buffer()
      |> deliver_replies()

    if new_state.closed and is_empty(new_state) do
      {:stop, :normal, new_state}
    else
      {:noreply, new_state}
    end
  end

  defp answer_receivers(%{receivers: receivers} = state) do
    with {{:value, receiver}, new_receivers} <- :queue.out(receivers),
         {:ok, value, new_state} <- next_value(state) do
      new_state
      |> Map.replace!(:receivers, new_receivers)
      |> Map.update!(:to_reply, &[{receiver, value} | &1])
      |> answer_receivers()
    else
      _ ->
        state
    end
  end

  defp update_buffer(%{senders: senders, buffer: buffer} = state) do
    with {{:value, {sender, value}}, new_senders} <- :queue.out(senders),
         {:ok, new_buffer} <- Buffer.put(buffer, value) do
      state
      |> Map.replace!(:senders, new_senders)
      |> Map.replace!(:buffer, new_buffer)
      |> Map.update!(:to_reply, &[{sender, :ok} | &1])
      |> update_buffer()
    else
      _ -> state
    end
  end

  defp next_value(state) do
    case Buffer.next(state.buffer) do
      {:ok, value, new_buffer} ->
        new_state = Map.replace!(state, :buffer, new_buffer)

        {:ok, value, new_state}

      :empty ->
        case :queue.out(state.senders) do
          {{:value, {sender, value}}, new_senders} ->
            new_state =
              state
              |> Map.replace!(:senders, new_senders)
              |> Map.update!(:to_reply, &[{sender, :ok} | &1])

            {:ok, value, new_state}

          {:empty, _senders} ->
            :empty
        end
    end
  end

  defp deliver_replies(state) do
    Enum.each(state.to_reply, fn {{client, monitor_ref}, reply} ->
      GenServer.reply(client, reply)

      Process.demonitor(monitor_ref)
    end)

    Map.replace!(state, :to_reply, [])
  end

  defp is_empty(%{buffer: buffer, senders: senders}) do
    :queue.is_empty(senders) && Buffer.next(buffer) == :empty
  end

  defp clear_dead_process(state, ref) do
    state
    |> Map.update!(:senders, fn senders ->
      :queue.filter(fn {{{_from, _ref}, sender_ref}, _val} -> sender_ref != ref end, senders)
    end)
    |> Map.update!(:receivers, fn receivers ->
      :queue.filter(fn {{_from, _ref}, receiver_ref} -> receiver_ref != ref end, receivers)
    end)
  end
end
