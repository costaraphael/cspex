defmodule CSP.Mixfile do
  use Mix.Project

  def project do
    [app: :cspex,
     version: "0.1.0",
     elixir: "~> 1.1",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps,
     description: description,
     package: package]
  end

  def application do
    []
  end

  def package do
    
  end

  def description do
    """
    A library that brings all the CSP joy to the Elixir land.
    """
  end

  defp deps do
    [{:exactor, "~> 2.2.0"}]
  end
end
