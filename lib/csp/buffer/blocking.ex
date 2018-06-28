defmodule CSP.Buffer.Blocking do
  @moduledoc ~S"""
  A buffer that only allows a certain amount of values to be put into it.

  ## Example

      iex> buffer = CSP.Buffer.Blocking.new(1)
      iex> {:ok, buffer} = CSP.Buffer.put(buffer, :foo)
      iex> CSP.Buffer.put(buffer, :bar)
      :error
      iex> {:ok, value, buffer} = CSP.Buffer.next(buffer)
      iex> value
      :foo
      iex> {:ok, buffer} = CSP.Buffer.put(buffer, :bar)
      iex> {:ok, value, buffer} = CSP.Buffer.next(buffer)
      iex> value
      :bar
      iex> CSP.Buffer.next(buffer)
      :empty
  """

  defstruct [items: :queue.new(), size: nil]

  @type t() :: %__MODULE__{}

  @doc ~S"""
  Creates a new buffer with the informed size.
  """
  @spec new(non_neg_integer()) :: t()
  def new(size) do
    %__MODULE__{size: size}
  end

  defimpl CSP.Buffer do
    alias CSP.Buffer.Blocking

    def put(buffer, value) do
      current_size = :queue.len(buffer.items)

      if current_size < buffer.size do
        new_buffer = %Blocking{buffer | items: :queue.in(value, buffer.items)}

        {:ok, new_buffer}
      else
        :error
      end
    end

    def next(buffer) do
      case :queue.out(buffer.items) do
        {{:value, value}, new_items} ->
          new_buffer = %Blocking{buffer | items: new_items}

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
        "#CSP.Buffer.Blocking<",
        concat(["size: ", size, ", "]),
        concat("items: ", items),
        ">"
      ])
    end
  end
end
