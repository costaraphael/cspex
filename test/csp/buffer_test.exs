defmodule CSP.BufferTest do
  use ExUnit.Case

  doctest CSP.Buffer.Blocking
  doctest CSP.Buffer.Sliding
  doctest CSP.Buffer.Dropping
end
