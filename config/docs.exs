import Config

config :logger, :console,
  format: "[$level] $message\n",
  metadata: [:module, :function],
  colors: [enabled: true],
  # this ensures it goes to stdout
  device: :standard_io
