import Config

config :logger, :console,
  format: "[$level] $message\n",
  metadata: [:module, :function],
  colors: [enabled: true],
  # this ensures it goes to stdout
  device: :standard_io

config :exvcr,
  vcr_cassette_library_dir: "test/support/fixtures/vcr_cassettes",
  custom_cassette_library_dir: "test/support/fixtures/custom_cassettes",
  filter_request_headers: ["Authorization", "OpenAI-Organization", "OpenAI-Project"],
  response_headers_blacklist: ["set-cookie"]

#   custom_cassette_library_dir: "fixture/custom_cassettes",
#   filter_sensitive_data: [
#     [pattern: "<PASSWORD>.+</PASSWORD>", placeholder: "PASSWORD_PLACEHOLDER"]
#   ],
#   filter_url_params: false,
#   filter_request_headers: [],
#   response_headers_blacklist: []
