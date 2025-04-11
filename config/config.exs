import Config

config(:openai_ex_pipeline, :ansi_enabled, true)

config(:elixir, :ansi_enabled, true)
import_config "#{config_env()}.exs"
