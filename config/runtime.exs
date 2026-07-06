import Config

# Runtime configuration for production and other environments.
# This file is evaluated at runtime, allowing for environment variable configuration.

# Example configuration - customize these values for your SDK
# config :your_package_name,
#   base_url: System.get_env("API_BASE_URL", "https://api.example.com"),
#   pool_size: String.to_integer(System.get_env("API_POOL_SIZE", "25")),
#   pool_count: String.to_integer(System.get_env("API_POOL_COUNT", "1")),
#   connect_timeout: String.to_integer(System.get_env("API_CONNECT_TIMEOUT", "5000"))

# API Configuration
# The base URL will be replaced by the setup script with your actual values
# config :your_package_name,
#   base_url: System.get_env("API_BASE_URL", "https://api.example.com")

# Connection Pool Configuration
# Adjust these values based on your expected load
# config :your_package_name,
#   pool_size: String.to_integer(System.get_env("HTTP_POOL_SIZE", "25")),
#   pool_count: String.to_integer(System.get_env("HTTP_POOL_COUNT", "1")),
#   connect_timeout: String.to_integer(System.get_env("HTTP_CONNECT_TIMEOUT", "5000"))

# Authentication Configuration (if needed)
# config :your_package_name,
#   api_key: System.get_env("API_KEY"),
#   api_secret: System.get_env("API_SECRET")

# Logging Configuration
if config_env() == :prod do
  config :logger,
    level: :info
end

if config_env() == :dev do
  config :logger,
    level: :debug
end
