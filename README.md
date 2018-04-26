# CSPEx

[![Hex.pm](https://img.shields.io/hexpm/v/cspex.svg?style=flat-square)](https://hex.pm/packages/cspex)
[![Hex.pm](https://img.shields.io/hexpm/dt/cspex.svg?style=flat-square)](https://hex.pm/packages/cspex)


A library that brings all the [CSP](https://en.wikipedia.org/wiki/Communicating_sequential_processes) joy to the Elixir land.

The aim of this library is to make it simple to work with [CSP channels](https://en.wikipedia.org/wiki/Channel_(programming))
alongside Elixir actors and supervision trees, so that we can have
another tool in our pockets, choosing it where it fits best.

Highly inspired on Go channels and Clojure core.async library.

Suggestions and pull requests are more than welcome.

## Examples

You can simply create a channel and pass it to other processes:

```elixir
channel = Channel.new

pid = spawn_link fn ->
  # This line will block until the data is read
  Channel.put(channel, :some)
  Channel.put(channel, :data)
end

Process.alive?(pid) #=> true

Channel.get(channel) #=> :some
Process.alive?(pid) #=> true

Channel.get(channel) #=> :data
Process.alive?(pid) #=> false
```

Or you can use a channel as part of a supervision tree:

```elixir
import Supervisor.Spec

children = [
  worker(Channel, [[name: MyApp.Channel]])
]

{:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one)

spawn_link fn ->
  # This line will block until some data is written to the channel
  data = Channel.get(MyApp.Channel)

  IO.puts "I read #{inspect data} from the channel."
end

Channel.put(MyApp.Channel, :data)
```

In any of the cases you can use a channel like any Enumerable or Colectable:

```elixir
# Wraps the process name into a channel struct
# Works with PIDs too
my_channel = Channel.wrap(MyApp.Channel)

spawn_link fn ->
  # Blocks until all the values can be written
  Enum.into(1..10, my_channel)
end

# The buffer size means how many values I can put in a channel until it
# starts blocking.
other_channel = Channel.new(buffer_size: 10)

# The code bellow will block until the channel "my_channel" is closed.
for x <- my_channel, into: other_channel do
  x * 2
end
```

## Installing

Add the dependency to the mix.exs file:

```elixir
deps: [{:cspex, "~> x.x.x"}, ...]
```

Add the following snippet to anywhere you want to use it:

```elixir
use CSP
```

Be happy!

## Documentation

Online documentation is available [here](http://hexdocs.pm/cspex).

## License

The CSPEx source code is licensed under the [MIT License](https://github.com/costaraphael/cspex/blob/master/LICENSE)
