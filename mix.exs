defmodule CSP.Mixfile do
  use Mix.Project

  def project do
    [
      app: :cspex,
      version: "2.0.0-beta",
      name: "CSPEx",
      source_url: "https://github.com/vidalraphael/cspex",
      elixir: "~> 1.4",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def package do
    [
      maintainers: ["Raphael Vidal"],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/vidalraphael/cspex"}
    ]
  end

  def docs do
    [main: "CSP", source_url: "https://github.com/vidalraphael/cspex"]
  end

  def description do
    """
    A library that brings all the CSP joy to the Elixir land.
    """
  end

  defp deps do
    [
      {:ex_doc, "~> 0.16", only: :dev, runtime: false}
    ]
  end
end
