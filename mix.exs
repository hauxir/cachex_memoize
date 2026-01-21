defmodule CachexMemoize.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/hauxir/cachex_memoize"

  def project do
    [
      app: :cachex_memoize,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "CachexMemoize",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:cachex, "~> 3.6 or ~> 4.0"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    A drop-in replacement for the Memoize library using Cachex.
    Provides the `defmemo` macro for easy function memoization with TTL support.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Haukur Rosinkranz"]
    ]
  end

  defp docs do
    [
      main: "CachexMemoize",
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
