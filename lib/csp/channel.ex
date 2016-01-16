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

      Enum.into(1..10, channel) # This line will block until someone reads all
                                # the ten values.

  ## Example

  An example using a channel in a supervision tree:

      use CSP
      import Supervisor.Spec

      children = [
        worker(Channel, [[name: MyApp.Channel, buffer_size: 10]])
      ]

      {:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one)

      # You can use all the functions with the registered name instead
      # of the Channel struct
      Channel.put(MyApp.Channel, :data)
      Channel.put(MyApp.Channel, :other)

      Channel.get(MyApp.Channel) #=> :data
      Channel.get(MyApp.Channel) #=> :other

      # If you want to use it in a list comprehension or Enumerable function
      # just call `CSP.Channel.wrap/1`
      channel = Channel.wrap(MyApp.Channel)

      Enum.into(1..5, channel)
      Enum.count(channel) #=> 5

  You can use channels in any part of list comprehensions, just remember use
  a buffer or run it in a separated process:

      channel = Enum.into(1..5, Channel.new(buffer_size: 5))

      :ok = Channel.close(channel)

      other_channel = for x <- channel, into: Channel.new(buffer_size: 5) do
        x * 2
      end

      :ok = Channel.close(other_channel)

      Enum.to_list(other_channel) #=> [2, 4, 6, 8, 10]
  """

  defstruct [:ref]

  @default_options [buffer_size: 0, buffer_type: :blocking]
  @server_module CSP.Channel.Server

  @type options :: [option]

  @type option :: {:buffer_size, non_neg_integer} |
                  {:buffer_type, buffer_type} |
                  {:name, GenServer.name}

  @type buffer_type :: :blocking | :sliding | :dropping

  @type channel_ref :: term | t

  @type t :: %__MODULE__{ref: term}

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

      iex> channel = Channel.new
      iex> spawn_link(fn -> Channel.put(channel, :data) end)
      iex> Channel.get(channel)
      :data
  """
  @spec new(options) :: t
  def new(options \\ []) do
    {:ok, pid} = start_link(options)

    %__MODULE__{ref: pid}
  end

  @doc """
  Wraps the PID or registered name in a Channel struct.

  If the passed in value is already a Channel struct, return it unchanged.
  """
  @spec wrap(channel_ref) :: t
  def wrap(%__MODULE__{} = channel), do: channel
  def wrap(channel), do: %__MODULE__{ref: channel}

  @doc """
  Function responsible for fetching a value of the channel.

  It will block until a value is inserted in the channel or it is closed.
  """
  @spec get(channel_ref) :: term
  def get(%__MODULE__{} = channel), do: get(channel.ref)
  def get(channel) do
    GenServer.call(channel, :get, :infinity)
  end

  @doc """
  Function responsible for putting a value in the channel.

  It may block until a value is fetched deppending on
  the buffer type of the channel.
  """
  @spec put(channel_ref, term) :: :ok
  def put(%__MODULE__{} = channel, item), do: put(channel.ref, item)
  def put(channel, item) do
    GenServer.call(channel, {:put, item}, :infinity)
  end

  @doc """
  Function responsible for closing a channel.
  """
  @spec close(channel_ref) :: :ok
  def close(%__MODULE__{} = channel), do: close(channel.ref)
  def close(channel) do
    GenServer.call(channel, :close, :infinity)
  end

  @doc """
  Returns `true` if the channel is closed or `false` otherwise.
  """
  @spec closed?(channel_ref) :: boolean
  def closed?(%__MODULE__{} = channel), do: closed?(channel.ref)
  def closed?(channel) do
    GenServer.call(channel, :"closed?", :infinity)
  end

  @doc """
  Returns the current size of the channel.
  """
  @spec size(channel_ref) :: non_neg_integer
  def size(%__MODULE__{} = channel), do: size(channel.ref)
  def size(channel) do
    GenServer.call(channel, :size, :infinity)
  end

  @doc """
  Returns `true` or `false` wheter the value is present on the channel.
  """
  @spec member?(channel_ref, term) :: boolean
  def member?(%__MODULE__{} = channel, value), do: member?(channel.ref, value)
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
      is_pid(channel.ref) && Process.alive?(channel.ref) && CSP.Channel.closed?(channel) ->
        "closed"
      is_pid(channel.ref) && Process.alive?(channel.ref) ->
        "open"
      :otherwise ->
        "not_channel"
    end

    concat ["#Channel<ref=", to_doc(channel.ref, opts), ", state=", state, ">"]
  end
end
