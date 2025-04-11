defmodule OpenaiExPipeline.MixProject do
  use Mix.Project
  @version "0.0.1"
  def project do
    [
      app: :openai_ex_pipeline,
      version: version(),
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      package: package(),
      description: description(),
      extra_applications: [:logger],
      source_url: "https://github.com/r26d/openai_ex_pipeline",
      docs: docs(),
      preferred_cli_env: [

        vcr: :test,
        "vcr.delete": :test,
        "vcr.check": :test,
        "vcr.show": :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test
      ]
    ]
  end

  defp package do
    [
      files: [
        "lib",
        "mix.exs",
        "README*",
        "LICENSE*"
      ],
      maintainers: ["Dirk Elmendorf"],
      description: description(),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/r26D/openai_ex_pipeline"
      }
    ]
  end

  defp description do
    """
     This builds on top of the OpenAIEx library to provide a more Elixir-friendly interface.
    """
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      ansi_enabled: true
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  # adding in support to handle the seed
  defp elixirc_paths(:dev), do: ["lib"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:openai_ex, "~> 0.9.3"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:mix_test_watch, "~> 1.2", only: :dev, runtime: false},
      {:ex_unit_notifier, "~> 1.3", only: :test},
      {:patch, "~> 0.15.0", only: [:test]},
      {:exvcr, "~> 0.17", only: :test},
      {:excoveralls, "~> 0.18.5", only: :test}
      #  {:ex_export, "~> 0.8.2"}
    ]
  end

  def version(), do: @version

  defp aliases do
    [
      tag:
        "cmd  git tag -a v#{version()} -m \\'Version #{version()}\\' ;git push origin v#{version()}",
      tags: "cmd git tag --list 'v*'",
      publish: ["docs", "cmd echo \$HEX_LOCAL_PASSWORD | mix hex.publish --yes"],
      prettier: "format \"mix.exs\" \"{lib,test}/**/*.{ex,exs}\""
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: "https://github.com/r26d/openai_ex_pipeline",
      source_ref: "v#{version()}",
      api_reference: true,
      extras: ["README.md", "LICENSE.md"]
    ]
  end
end
