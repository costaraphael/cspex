defmodule CSP.Buffer.Sliding do
  @moduledoc ~S"""
  A buffer that starts removing old elements once it reaches it's maximum size.

  ## Example

      iex> buffer = CSP.Buffer.Sliding.new(2)
      iex> {:ok, buffer} = CSP.Buffer.put(buffer, :foo)
      iex> {:ok, buffer} = CSP.Buffer.put(buffer, :bar)
      iex> {:ok, buffer} = CSP.Buffer.put(buffer, :baz)
      iex> {:ok, value, buffer} = CSP.Buffer.next(buffer)
      iex> value
      :bar
      iex> {:ok, value, buffer} = CSP.Buffer.next(buffer)
      iex> value
      :baz
      iex> CSP.Buffer.next(buffer)
      :empty
  """

  defstruct items: :queue.new(), size: nil

  @type t() :: %__MODULE__{}

  @doc ~S"""
  Creates a new buffer with the informed size.
  """
  @spec new(non_neg_integer()) :: t()
  def new(size) do
    %__MODULE__{size: size}
  end

  defimpl CSP.Buffer do
    alias CSP.Buffer.Sliding

    def put(buffer, value) do
      items =
        if :queue.len(buffer.items) < buffer.size do
          buffer.items
        else
          :queue.drop(buffer.items)
        end

      new_buffer = %Sliding{buffer | items: :queue.in(value, items)}

      {:ok, new_buffer}
    end

    def next(buffer) do
      case :queue.out(buffer.items) do
        {{:value, value}, new_items} ->
          new_buffer = %Sliding{buffer | items: new_items}

          {:ok, value, new_buffer}

        {:empty, _items} ->
          :empty
      end
    end
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(buffer, opts) do
      size = to_doc(buffer.size, opts)

      items =
        buffer.items
        |> :queue.to_list()
        |> to_doc(opts)

      concat([
        "#CSP.Buffer.Sliding<",
        concat(["size: ", size, ", "]),
        concat("items: ", items),
        ">"
      ])
    end
  end
end
