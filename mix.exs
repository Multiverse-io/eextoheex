defmodule EexToHeex.MixProject do
  use Mix.Project

  def project do
    [
      app: :eextoheex,
      version: "0.1.5",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      description: "Automatic conversion of eex templates to heex",
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:eex, :logger, :briefly]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:html_entities, "~> 0.5"},
      {:phoenix_live_view, "~> 0.17.5", runtime: false},
      {:briefly, "~> 0.5.1"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp escript do
    [main_module: EexToHeex.CLI]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub Readme" => "https://github.com/Multiverse-io/eextoheex/blob/main/README.md",
        source_url: "https://github.com/Multiverse-io/eextoheex"
      }
    ]
  end
end
