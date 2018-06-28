defprotocol CSP.Buffer do
  @moduledoc ~S"""
  Protocol that should be implemented for any struct that wants to act like a buffer.
  """

  @doc """
  Puts a value in the buffer.

  Should return the new buffer or error if the value cannot be put for some reason.
  """
  @spec put(t(), term()) :: {:ok, t()} | :error
  def put(buffer, value)

  @doc """
  Reads a value from the buffer.

  Should return the value and the new buffer or the atom `:empty` if there are
  no more values left.
  """
  @spec next(t()) :: {:ok, term(), t()} | :empty
  def next(buffer)
end
