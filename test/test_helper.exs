# Start Cachex for tests
{:ok, _} = Application.ensure_all_started(:cachex)
{:ok, _} = Cachex.start_link(name: :cachex_memoize)

ExUnit.start()
