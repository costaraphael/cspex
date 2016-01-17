# CSPEx

[![Hex.pm](https://img.shields.io/hexpm/v/cspex.svg?style=flat-square)](https://hex.pm/packages/cspex)
[![Hex.pm](https://img.shields.io/hexpm/dt/cspex.svg?style=flat-square)](https://hex.pm/packages/cspex)


A library that brings all the CSP joy to the Elixir land.

Highly inspired on Clojure's core.async library.

Suggestions and pull requests are more than welcome.

## Why would I use CSPEx?

There are some cases where it is more simple and practical to know only that
someone is getting a message, instead of dealing with who should receive a
message, like a bunch of workers that reads through a channel and do some work,
while a master simply writes to it.

## Usage

* Add the dependency to the mix.exs file:

```elixir
deps: [{:cspex, "~> x.x.x"}, ...]
```

* Add the following snippet to anywhere you want to use it:

```elixir
use CSP
```

* Be happy!

## Documentation

Online documentation is available [here](http://hexdocs.pm/cspex).
