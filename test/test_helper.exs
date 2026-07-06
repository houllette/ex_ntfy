# Test Helper
# This file is run before all tests

# Configure ExUnit
ExUnit.start()

# Start Mox for mocking
Mox.defmock(HTTPClientMock, for: Tesla.Adapter)

# Application will be started automatically by Mix
# but we ensure it's running for integration tests
{:ok, _} = Application.ensure_all_started(:bypass)
