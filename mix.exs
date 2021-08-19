defmodule EexToHeex.MixProject do
  use Mix.Project

  def project do
    [
      app: :eextoheex,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :briefly]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:html_entities, "~> 0.5"},
      {:phoenix_live_view, "~> 0.16.0"},
      {:briefly, "~> 0.3"}
    ]
  end

  defp escript do
    [main_module: EexToHeex.CLI]
  end
end
