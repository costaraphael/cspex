defmodule CSP.Channel do
  @moduledoc """
  Module used to create and manage Channels

  ## Options

  There are some options that may be used to change a channel behavior,
  but the channel's options can only be set during it's creation.

  The available options are:

    * `name` - Registers the channel proccess with a name. Note that the
    naming constraints are the same applied to a `GenServer`.
    * `buffer_type` - The type of the buffer used in the channel (by default
    `:blocking`).
    * `buffer_size` - The maximum capacity of the channel's buffer (by default
    `0`).

  ## Buffer types

  There are three suported buffer types:

    * `:blocking` - The channel never blocks until the buffer capacity is full.
    * `:sliding` - The channel never blocks, but when the buffer is full, it
    starts discarding the older values on it to make room for the newer ones.
    * `:dropping` - The channel never blocks, but when the buffer is full, it
    starts discarding any new values that are put on it, keeping the old ones.

  ## Collections interoperability

  You can use a channel just like any collection:

      channel = Channel.new
      other_channel = Channel.new

      spawn fn -> Enum.into(channel, other_channel) end

      Channel.put(channel, "some_data")
      Channel.get(other_channel) #=> "some_data"

  All functions from `Enum` and `Stream` are available, but you must take into
  consideration the blocking operations:

      channel = Channel.new

      Enum.into(1..10, channel) # This line will block until someone reads the
      ten values.

  ## Example


  """

  defstruct [:pid]

  @default_options [buffer_size: 0, buffer_type: :blocking]
  @server_module CSP.Channel.Server

  @type options :: [option]

  @type option :: {:buffer_size, non_neg_integer} |
                  {:buffer_type, buffer_type} |
                  {:name, GenServer.name}

  @type buffer_type :: :blocking | :sliding | :dropping

  @type channel_ref :: term | t

  @type t :: %__MODULE__{pid: term}

  @doc """
  Function responsible for the starting of the channel.

  Ideal for using a CSP in a supervision tree.
  """
  @spec start_link(options) :: GenServer.on_start
  def start_link(options \\ []) do
    options = options ++ @default_options

    GenServer.start_link(@server_module, options, name: options[:name])
  end

  @doc """
  Non-linking version of `CSP.Channel.start_link/1`
  """
  @spec start(options) :: GenServer.on_start
  def start(options \\ []) do
    options = options ++ @default_options

    GenServer.start(@server_module, options, name: options[:name])
  end

  @doc """
  Function responsible for creating a new channel.

  Useful for using channels outside of a supervision tree.

  ## Example

      iex> chann = CSP.Channel.new
      iex> spawn_link(fn -> CSP.Channel.put(chann, :data) end)
      iex> CSP.Channel.get(chann)
      :data
  """
  @spec new(options) :: t
  def new(options \\ []) do
    {:ok, pid} = start_link(options)

    %__MODULE__{pid: pid}
  end

  @doc """
  Function responsible for fetching a value of the channel.

  It will block until a value is inserted in the channel or it is closed.
  """
  @spec get(channel_ref) :: term
  def get(%__MODULE__{} = channel), do: get(channel.pid)
  def get(channel) do
    GenServer.call(channel, :get, :infinity)
  end

  @doc """
  Function responsible for putting a value in the channel.

  It may block until a value is fetched deppending on
  the buffer type of the channel.
  """
  @spec put(channel_ref, term) :: :ok
  def put(%__MODULE__{} = channel, item), do: put(channel.pid, item)
  def put(channel, item) do
    GenServer.call(channel, {:put, item}, :infinity)
  end

  @doc """
  Function responsible for closing a channel.
  """
  @spec close(channel_ref) :: :ok
  def close(%__MODULE__{} = channel), do: close(channel.pid)
  def close(channel) do
    GenServer.call(channel, :close, :infinity)
  end

  @doc """
  Returns `true` or `false` wheter the channel is closed.
  """
  @spec closed?(channel_ref) :: boolean
  def closed?(%__MODULE__{} = channel), do: closed?(channel.pid)
  def closed?(channel) do
    GenServer.call(channel, :"closed?", :infinity)
  end

  @doc """
  Returns the current size of the channel.
  """
  @spec size(channel_ref) :: non_neg_integer
  def size(%__MODULE__{} = channel), do: size(channel.pid)
  def size(channel) do
    GenServer.call(channel, :size, :infinity)
  end

  @doc """
  Returns `true` or `false` wheter the value is present on the channel.
  """
  @spec member?(channel_ref, term) :: boolean
  def member?(%__MODULE__{} = channel, value), do: member?(channel.pid, value)
  def member?(channel, value) do
    GenServer.call(channel, {:"member?", value}, :infinity)
  end
end

defimpl Enumerable, for: CSP.Channel do
  def reduce(_channel, {:halt, acc}, _fun),  do: {:halted, acc}
  def reduce(channel, {:suspend, acc}, fun), do: {:suspended, acc, &reduce(channel, &1, fun)}
  def reduce(channel, {:cont, acc}, fun) do
    case CSP.Channel.get(channel) do
      nil ->
        {:done, acc}
      value ->
        reduce(channel, fun.(value, acc), fun)
    end
  end

  def member?(channel, value), do: {:ok, CSP.Channel.member?(channel, value)}
  def count(channel),          do: {:ok, CSP.Channel.size(channel)}
end

defimpl Collectable, for: CSP.Channel do
  def into(channel) do
    {channel, fn
      channel, {:cont, x} ->
        :ok = CSP.Channel.put(channel, x)
        channel

      channel, :done ->
        channel

      _, :halt ->
        :ok

    end}
  end
end

defimpl Inspect, for: CSP.Channel do
  import Inspect.Algebra

  def inspect(channel, opts) do
    state = cond do
      is_pid(channel.pid) && Process.alive?(channel.pid) && CSP.Channel.closed?(channel) ->
        "closed"
      is_pid(channel.pid) && Process.alive?(channel.pid) ->
        "open"
      :otherwise ->
        "not_channel"
    end

    concat ["#Channel<pid=", to_doc(channel.pid, opts), ", state=", state, ">"]
  end
end
