defmodule CSP do
  @moduledoc """
  Library created to bring all the CSP joy to the Elixir lang.

  Just put

      use CSP

  on the top of your module and you are good to go.

  Check out the documentation for `CSP.Channel` for more details.
  """

  defmacro __using__(_) do
    quote do
      alias CSP.Channel 
    end
  end
end
