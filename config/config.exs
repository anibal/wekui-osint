# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# These enable behaviors that will become the default in the next major
# version of Ash. Setting them now opts your application into the new
# behavior and ensures a seamless upgrade. See the backwards compatibility
# guide for an explanation of each setting:
# https://hexdocs.pm/ash/backwards-compatibility-config.html
config :ash,
  allow_forbidden_field_for_relationships_by_default?: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true,
  redact_sensitive_values_in_errors?: true

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [section_order: [:resources, :policies, :authorization, :domain, :execution]]
  ]

config :wekui,
  ecto_repos: [Wekui.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [
    Wekui.Narrative,
    Wekui.Judgment,
    Wekui.Acquisition,
    Wekui.Capture,
    Wekui.Core,
    Wekui.Taxonomy
  ]

# The persons red line's allowlist (F54): people who MAY be named in a Claim —
# public officials and figures acting in a public capacity. Everything not here
# and not gazetteer geography is treated as a private individual and refused by
# `Wekui.Narrative.Validations.NoPrivateName`. Adding a name here is a deliberate
# act with dignity and safety weight: victims, survivors, the missing and the
# dead NEVER belong on this list.
config :wekui, :public_figures, [
  # Venezuela — government
  "Nicolás Maduro",
  "Delcy Rodríguez",
  "Jorge Rodríguez",
  "Diosdado Cabello",
  # Venezuela — opposition
  "María Corina Machado",
  "Edmundo González",
  # foreign heads of state / officials acting officially
  "Nayib Bukele",
  "Donald Trump",
  "Gustavo Petro",
  "Claudia Sheinbaum",
  "Luiz Inácio Lula da Silva"
]

# The inference worker: DeepSeek via DeepInfra's OpenAI-compatible endpoint. The
# api_key comes from the environment (runtime.exs); tests swap Req for a Req.Test plug
# so the network never enters the suite.
config :wekui, :worker_client, Wekui.Clients.Worker.Live

config :wekui, :deepinfra,
  base_url: "https://api.deepinfra.com/v1/openai",
  model: "deepseek-ai/DeepSeek-V4-Flash",
  receive_timeout: 180_000

# SQLite pragmas shared across all environments (dev/test/runtime.exs only add
# :database and :pool_size). WAL allows concurrent readers during a write,
# NORMAL synchronous relies on WAL for durability instead of fsync-per-commit,
# and the larger cache/mmap trade memory for fewer disk reads.
config :wekui, Wekui.Repo,
  journal_mode: :wal,
  synchronous: :normal,
  foreign_keys: :on,
  busy_timeout: 5_000,
  cache_size: -64_000,
  temp_store: :memory,
  custom_pragmas: [mmap_size: 268_435_456]

# Configures the endpoint
config :wekui, WekuiWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: WekuiWeb.ErrorHTML, json: WekuiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Wekui.PubSub,
  live_view: [signing_salt: "1H1uxzNa"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :wekui, Wekui.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  wekui: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  wekui: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
