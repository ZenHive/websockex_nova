defmodule WebsockexNova.MixProject do
  use Mix.Project

  def project do
    [
      app: :websockex_nova,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: dialyzer(),
      aliases: aliases(),
      preferred_cli_env: [
        dialyzer: :dev,
        credo: :dev,
        sobelow: :dev,
        lint: :dev,
        typecheck: :dev,
        security: :dev,
        coverage: :test,
        check: :dev,
        docs: :dev
      ]
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {WebsockexNova.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:gun, "~> 2.2"},
      {:jason, "~> 1.4"},

      # Static code analysis
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},

      # Documentation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:mox, "~> 1.0", only: :test},
      # Security scanning
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      # Used for mock WebSocket server in tests
      {:cowboy, "~> 2.10", only: :test},

      # WebSock for standardized WebSocket handling
      {:websock, "~> 0.5", only: :test},
      {:websock_adapter, "~> 0.5", only: :test},

      # Required for Plug.Cowboy.http/3
      {:plug_cowboy, "~> 2.6", only: :test},
      {:stream_data, "~> 1.0", only: [:test, :dev]},
      {:styler, "~> 1.4", only: [:dev, :test], runtime: false},

      # For generating temporary files (certificates) in tests
      {:temp, "~> 0.4", only: :test},

      # For generating self-signed certificates in tests
      {:x509, "~> 0.8", only: :test},
      {:certifi, "~> 2.5"},
      {:telemetry, "~> 1.3"},
      {:meck, "~> 0.9", only: :test},
      {:mint_web_socket, "~> 1.0"}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp dialyzer do
    [
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix, :ex_unit]
    ]
  end

  # Add aliases for code quality tools
  defp aliases do
    [
      lint: ["credo --strict"],
      typecheck: ["dialyzer"],
      security: ["sobelow --exit --config"],
      coverage: ["test --cover"],
      docs: ["docs"],
      check: [
        "lint",
        "typecheck",
        "security",
        "coverage"
      ],
      rebuild: ["deps.clean --all", "clean", "deps.get", "compile", "dialyzer", "credo --strict"]
    ]
  end
end
