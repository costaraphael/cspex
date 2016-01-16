defmodule CSP.Mixfile do
  use Mix.Project

  def project do
    [app: :cspex,
     version: "0.1.0",
     name: "CSPEx",
     source_url: "https://github.com/vidalraphael/cspex",
     elixir: "~> 1.1",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps,
     description: description,
     docs: docs,
     package: package]
  end

  def application do
    []
  end

  def package do
    [maintainers: ["Raphael Vidal"],
     licenses: ["MIT"],
     links: %{"Github" => "https://github.com/vidalraphael/cspex"}]
  end

  def docs do
    [main: "CSP",
     source_url: "https://github.com/vidalraphael/cspex"]
  end

  def description do
    """
    A library that brings all the CSP joy to the Elixir land.
    """
  end

  defp deps do
    [{:exactor, "~> 2.2.0"},
     {:ex_doc, "~> 0.11", only: :dev}]
  end
end
