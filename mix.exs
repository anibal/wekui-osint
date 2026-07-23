defmodule Wekui.MixProject do
  use Mix.Project

  def project do
    [
      app: :wekui,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      usage_rules: usage_rules(),
      consolidate_protocols: Mix.env() != :dev
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Wekui.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:ash_state_machine, "~> 0.2"},
      {:ash_sqlite, "~> 0.2"},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:ash, "~> 3.0"},
      {:usage_rules, "~> 1.0", only: [:dev]},
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ash.setup --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind wekui", "esbuild wekui"],
      "assets.deploy": [
        "tailwind wekui --minify",
        "esbuild wekui --minify",
        "phx.digest"
      ],
      precommit: [
        &docs_doctor/1,
        "compile --warning-as-errors",
        "deps.unlock --unused",
        "format",
        "test"
      ],
      "ash.setup": ["ash.setup", "run priv/repo/seeds.exs"]
    ]
  end

  # Guard the docs/ outline: fail on pages outside the outl dialect (which can
  # corrupt on outl's next write), skip silently when outl is not installed.
  # "no sidecar" warnings are allowed — pages are committed before adoption.
  defp docs_doctor(_args) do
    case System.find_executable("outl") do
      nil ->
        Mix.shell().info("outl not installed — skipping docs outline check")

      _outl ->
        {out, status} = System.cmd("outl", ["-w", "docs", "doctor"], stderr_to_stdout: true)

        if status != 0 or String.contains?(out, "outside outl dialect") do
          Mix.shell().error(out)
          Mix.raise("docs outline check failed — fix the pages flagged above")
        end
    end
  end

  defp usage_rules do
    [
      # Nothing is inlined into AGENTS.md/CLAUDE.md: always-on context stays
      # hand-curated (see the curation note at the top of AGENTS.md).
      # Framework rules are delivered as on-demand skills, one per activity,
      # so only the relevant rules enter the context window.
      skills: [
        location: ".claude/skills",
        build: [
          "ash-framework": [
            description:
              "Use when creating or changing Ash resources, domains, actions, relationships, policies, calculations, or running codegen/migrations — any domain change under lib/wekui/.",
            usage_rules: [:ash, ~r/^ash_/]
          ]
          # The fine-grained phoenix-* skills are hand-written pointers to
          # deps/phoenix/usage-rules/*.md (usage_rules can only build whole
          # packages into one skill). They read the installed version directly,
          # so they never go stale and need no sync.
        ]
      ]
    ]
  end
end
