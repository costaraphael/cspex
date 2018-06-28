defmodule CSP.Channel do
  @moduledoc """
  Module used to create and manage channels.

  ## Options

  There are some options that may be used to change a channel behavior,
  but the channel's options can only be set during it's creation.

  The available options are:

    * `name` - Registers the channel proccess with a name. Note that the
    naming constraints are the same applied to a `GenServer`.
    * `buffer` - A struct that implements the `CSP.Buffer` protocol. This library ships
    with three implementations: `CSP.Buffer.Blocking`, `CSP.Buffer.Dropping` and
    `CSP.Buffer.Sliding`. Check out their documentation for more information on how each
    one works.

  ## Using as a collection

  The `CSP.Channel` struct has underpinnings for working alongside the
  `Stream` and `Enum` modules. You can use a channel directly as a Collectable:

      channel = Channel.new()
      Enum.into([:some, :data], channel)

      channel = Channel.new()
      for x <- 1..4, into: channel do
        x * x
      end

  And you can also use the channel as an Enumerable:

      channel = Channel.new()
      Enum.take(channel, 2)

      channel = channel.new()
      for x <- channel do
        x * x
      end

  Just be mindful that just like the `put` and `get` operations can be blocking,
  so do these. One trick is to spin up a process to take care of feeding and
  reading the channel:

      channel = Channel.new()
      spawn_link(fn -> Enum.into([:some, :data], channel) end)
      Enum.take(channel, 2) # => [:some, :data]

  In the next section we will discuss some of the gotchas of using channels as
  Collectables/Enumerables.

  #### As a Collectable

  Every element that is fed into the channel causes a `put`operation, so be sure
  that there will be someone reading from your channel or that your channel has
  a buffer big enough to accommodate the incoming events.

  #### As an Enumerable

  Every element that is read from the channel causes a `get` operation. so be sure
  that there will be someone adding values to your channel.

  A thing to keep in mind while using channels as Enumerables is that they act like
  infinite streams, so eager functions that consume the whole stream
  (like `Enum.map/2` or `Enum.each/2`) will only return when the channel is closed
  (see `CSP.Channel.close/1`).

  Unless that is exactly what you want, use functions from the `Stream` module to
  build your processing pipeline and finish them with something like `Enum.take/2`
  or `Enum.take_while/2`.

  Another caveat of using channels as Enumerables is that filtering with
  `Stream.filter/2` or `Enum.filter/2` does not simply filter what you are going
  to read from the channel. It reads the values and then discards the rejected
  ones.

  If you just want to direct the filtered results elsewhere or partition the
  events between multiple consumers, use `CSP.Channel.partition/2` and
  `CSP.Channel.partition/3` respectively.

  The almost same thing would happen with `Enum.count/1` and `Enum.member?/2`,
  as the values would be read from the channel to get the result and be discarded
  afterwards. As an operation like this should not be done on a channel, an error
  is raised if those functions (and others similar to them) are called with a
  channel.

  Using the the Collectable/Enumerable implementation you can get some nice
  results, like this parallel map over a channel implementation:

      defmodule ChannelExtensions do
        alias CSP.Channel

        # Receive a channel, the number of workers
        # and a function to be called on each value.
        # Returns a channel with the results.
        def pmap(source, workers, fun) do
          # Create the results channel and a temporary channel just for cleanup.
          results = Channel.new()
          done = Channel.new()

          # Spin up the number of workers passed as argument.
          # Each worker stream values from on channel
          # to the other passing each to the function.
          # After the source is depleted, each worker puts
          # a message in the done channel.
          for _ <- 1..workers do
            Task.start_link(fn ->
              for value <- source, into: results, do: fun.(value)

              Channel.put(done, true)
            end)
          end

          # Spin up a cleanup process that blocks until all
          # the workers put a message in the done channel,
          # then closes both the done and the results channels.
          Task.start_link(fn ->
            Enum.take(done, workers)

            Channel.close(done)
            Channel.close(results)
          end)

          results
        end
      end

  ## OTP Compatibility

  Since channels are just GenServers, you can use a channel in a supervision tree:

      alias CSP.{
        Buffer,
        Channel
      }

      children = [
        {Channel, name: MyApp.Channel, buffer: Buffer.Blocking.new(10)}
      ]

      {:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one)

  You can use all the functions with the registered name instead of the channel struct:

      Channel.put(MyApp.Channel, :data)
      Channel.put(MyApp.Channel, :other)

      Channel.get(MyApp.Channel) #=> :data
      Channel.get(MyApp.Channel) #=> :other

  If you want to use it as a channel struct just call `CSP.Channel.wrap/1`:

      channel = Channel.wrap(MyApp.Channel)
      Enum.into(1..4, channel)
  """

  alias CSP.Buffer

  defstruct [:ref]

  @server_module CSP.Channel.Server

  @type options :: [option]

  @type option ::
          {:buffer, CSP.Buffer.t()}
          | {:buffer_size, non_neg_integer()}
          | {:buffer_type, buffer_type()}
          | {:name, GenServer.name()}

  @type buffer_type :: :blocking | :sliding | :dropping

  @type channel_ref :: term | t

  @type t :: %__MODULE__{ref: term()}

  @doc false
  def child_spec(options) do
    {buffer, name} = parse_options(options)

    %{
      id: name || __MODULE__,
      type: :worker,
      start: {__MODULE__, :start_link, [[buffer: buffer, name: name]]}
    }
  end

  @doc """
  Function responsible for the starting of the channel.

  Ideal for using a CSP in a supervision tree.
  """
  @spec start_link(options) :: GenServer.on_start()
  def start_link(options \\ []) do
    {buffer, name} = parse_options(options)

    GenServer.start_link(@server_module, buffer, name: name)
  end

  @doc """
  Non-linking version of `CSP.Channel.start_link/1`
  """
  @spec start(options) :: GenServer.on_start()
  def start(options \\ []) do
    {buffer, name} = parse_options(options)

    GenServer.start(@server_module, buffer, name: name)
  end

  @doc """
  Function responsible for creating a new channel.

  Useful for using channels outside of a supervision tree.

  ## Example

      iex> channel = Channel.new()
      iex> spawn_link(fn -> Channel.put(channel, :data) end)
      iex> Channel.get(channel)
      :data
  """
  @spec new(options) :: t
  def new(options \\ []) do
    {:ok, pid} = start_link(options)

    wrap(pid)
  end

  @doc """
  Wraps the PID or registered name in a Channel struct.

  If the passed in value is already a Channel struct, return it unchanged.

  ## Example

      iex> {:ok, pid} = Channel.start_link(buffer: CSP.Buffer.Blocking.new(5))
      iex> channel = Channel.wrap(pid)
      iex> Enum.into(1..5, channel)
      iex> Channel.close(channel)
      iex> Enum.to_list(channel)
      [1, 2, 3, 4, 5]

      iex> channel = Channel.new()
      iex> channel == Channel.wrap(channel)
      true
  """
  @spec wrap(channel_ref) :: t
  def wrap(%__MODULE__{} = channel), do: channel
  def wrap(channel), do: %__MODULE__{ref: channel}

  @doc """
  Function responsible for fetching a value of the channel.

  It will block until a value is inserted in the channel or it is closed.

  Always returns `nil` when the channel is closed.

  ## Example

      iex> channel = Channel.new()
      iex> spawn_link(fn -> Channel.put(channel, :data) end)
      iex> Channel.get(channel)
      :data
      iex> Channel.close(channel)
      iex> Channel.get(channel)
      nil
  """
  @spec get(channel_ref) :: term
  def get(%__MODULE__{} = channel), do: get(channel.ref)

  def get(channel) do
    try do
      GenServer.call(channel, :get, :infinity)
    catch
      :exit, {_, {GenServer, :call, [_, :get, _]}} ->
        nil
    end
  end

  @doc """
  Function responsible for putting a value in the channel.

  It may block until a value is fetched deppending on the buffer type of the
  channel.

  Raises if trying to put `nil` or if trying to put anything in a closed channel.

  ## Example

      iex> channel = Channel.new(buffer: CSP.Buffer.Blocking.new(5))
      iex> Channel.put(channel, :data)
      iex> Channel.put(channel, :other)
      iex> Enum.take(channel, 2)
      [:data, :other]
  """
  @spec put(channel_ref, term) :: :ok
  def put(%__MODULE__{} = channel, item), do: put(channel.ref, item)
  def put(_channel, nil), do: raise(ArgumentError, "Can't put nil on a channel.")

  def put(channel, item) do
    try do
      GenServer.call(channel, {:put, item}, :infinity)
    catch
      :exit, {_, {GenServer, :call, [_, {:put, _}, _]}} ->
        {:error, :closed}
    end
  end

  @doc """
  Function responsible for closing a channel.

  ## Example

      iex> channel = Channel.new()
      iex> Channel.closed?(channel)
      false
      iex> Channel.close(channel)
      iex> Channel.closed?(channel)
      true
  """
  @spec close(channel_ref) :: :ok
  def close(%__MODULE__{} = channel), do: close(channel.ref)

  def close(channel) do
    try do
      GenServer.call(channel, :close)
    catch
      :exit, {_, {GenServer, :call, [_, :close, _]}} ->
        :ok
    end
  end

  @doc """
  Returns `true` if the channel is closed or `false` otherwise.
  """
  @spec closed?(channel_ref) :: boolean
  def closed?(%__MODULE__{} = channel), do: closed?(channel.ref)

  def closed?(channel) do
    try do
      GenServer.call(channel, :closed?)
    catch
      :exit, {_, {GenServer, :call, [_, :closed?, _]}} ->
        true
    end
  end

  @doc """
  Creates a channel based on the given enumerables.

  The created channel is closed when the provided enumerables are depleted.

  ## Example

      iex> channel = Channel.from_enumerables([1..4, 5..8])
      iex> Enum.to_list(channel)
      [1, 2, 3, 4, 5, 6, 7, 8]
  """
  @spec from_enumerables([Enum.t()]) :: t
  def from_enumerables(enums) do
    result = new()

    Task.start_link(fn ->
      enums
      |> Stream.concat()
      |> Enum.into(result)

      close(result)
    end)

    result
  end

  @doc """
  Creates a channel based on the given enumerable.

  The created channel is closed when the enumerable is depleted.

  ## Example

      iex> channel = Channel.from_enumerable(1..4)
      iex> Enum.to_list(channel)
      [1, 2, 3, 4]
  """
  @spec from_enumerable(Enum.t()) :: t
  def from_enumerable(enum) do
    from_enumerables([enum])
  end

  @doc """
  Creates a channel that buffers events from a source channel.

  The created channel is closed when the source channel is closed.

  ## Example

      iex> unbuffered = Channel.new()
      iex> buffered = Channel.with_buffer(unbuffered, 5)
      iex> Enum.into(1..5, unbuffered)
      iex> Enum.take(buffered, 5)
      [1, 2, 3, 4, 5]
  """
  @spec with_buffer(t, non_neg_integer) :: t
  def with_buffer(source, size) do
    result = new(buffer: Buffer.Blocking.new(size))

    Task.start_link(fn ->
      Enum.into(source, result)

      close(result)
    end)

    result
  end

  @doc """
  Partitions a channel in two, according to the provided function.

  The created channels are closed when the source channel is closed.

  ### Important

  This function expects that you are going to simultaneously read from
  both channels, as an event that is stuck in one of them will block the other.

  If you just want to discard values from a channel, use `Stream.filter/2` or
  `Stream.reject/2`.

  ## Example

      iex> require Integer
      iex> channel = Channel.from_enumerable(1..4)
      iex> {even, odd} = Channel.partition(channel, &Integer.is_even/1)
      iex> Channel.get(odd)
      1
      iex> Channel.get(even)
      2
      iex> Channel.get(odd)
      3
      iex> Channel.get(even)
      4
  """
  @spec partition(t, (term -> boolean)) :: {t, t}
  def partition(source, fun) do
    %{true => left, false => right} = partition(source, [true, false], fun)

    {left, right}
  end

  @doc """
  Partitions events from one channel to an arbitrary number of other channels,
  according to the partitions definition and the hashing function.

  Returns a map with the partition as the name and the partition channel as
  the value.

  All the created channels are closed when the source channel is closed.

  ### Important

  This function expects that you are going to simultaneously read from
  all channels, as an event that is stuck in one of them will block the others.

  ## Example

      iex> channel = Channel.from_enumerable(1..10)
      iex> partitions = Channel.partition(channel, 0..3, &rem(&1, 4))
      iex> partitions
      ...> |> Enum.map(fn {key, channel} -> {key, Channel.with_buffer(channel, 5)} end)
      ...> |> Enum.map(fn {key, channel} -> {key, Enum.to_list(channel)} end)
      [{0, [4, 8]}, {1, [1, 5, 9]}, {2, [2, 6, 10]}, {3, [3, 7]}]
  """
  @spec partition(t, Enum.t(), (term -> term)) :: %{term => t}
  def partition(source, partitions, hashing_fun) do
    partitions = Map.new(partitions, &{&1, new()})

    Task.start_link(fn ->
      for value <- source do
        partition = hashing_fun.(value)

        case Map.fetch(partitions, partition) do
          {:ok, channel} ->
            put(channel, value)

          :error ->
            valid_partitions = Map.keys(partitions)

            raise """
            The partition #{inspect(partition)} returned by the hashing function is invalid.

            The valid partitions are: #{inspect(valid_partitions)}.
            """
        end
      end

      partitions
      |> Map.values()
      |> Enum.each(&close/1)
    end)

    partitions
  end

  defp parse_options(options) do
    buffer =
      case Keyword.fetch(options, :buffer) do
        {:ok, value} -> value
        :error -> parse_legacy_buffer(options)
      end

    {buffer, options[:name]}
  end

  defp parse_legacy_buffer(options) do
    size = Keyword.get(options, :buffer_size, 0)

    case Keyword.fetch(options, :buffer_type) do
      {:ok, :blocking} -> Buffer.Blocking.new(size)
      {:ok, :dropping} -> Buffer.Dropping.new(size)
      {:ok, :sliding} -> Buffer.Sliding.new(size)
      :error -> Buffer.Blocking.new(size)
    end
  end

  defimpl Enumerable do
    require Logger

    def reduce(_channel, {:halt, acc}, _fun) do
      {:halted, acc}
    end

    def reduce(channel, {:suspend, acc}, fun) do
      {:suspended, acc, &reduce(channel, &1, fun)}
    end

    def reduce(channel, {:cont, acc}, fun) do
      case CSP.Channel.get(channel) do
        nil ->
          {:done, acc}

        value ->
          reduce(channel, fun.(value, acc), fun)
      end
    end

    def member?(_channel, _value) do
      error()
    end

    def count(_channel) do
      error()
    end

    def slice(_channel) do
      error()
    end

    defp error do
      raise """
      Don't use a `CSP.Channel` in functions like `Enum.count/1`, `Enum.at/2` and
      `Enum.member?/2`, as they will fetch and discard events from the channel to
      get their results.

      When using the channel as an Enumerable, use only collection processing functions,
      preferably from the `Stream` module.
      """
    end
  end

  defimpl Collectable do
    def into(channel) do
      {channel,
       fn
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

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(channel, opts) do
      state =
        if CSP.Channel.closed?(channel) do
          "closed"
        else
          "open"
        end

      concat(["#Channel<ref=", to_doc(channel.ref, opts), ", state=", state, ">"])
    end
  end
end
