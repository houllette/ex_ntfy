import Config

# This file is responsible for configuring your application at compile-time.
# Configuration from this file will be compiled into your application and
# can NOT be changed at runtime.
#
# For runtime configuration, see config/runtime.exs

# Configure logging
config :logger,
  level: :info,
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

# Import environment specific config
import_config "#{config_env()}.exs"
