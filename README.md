# CachexMemoize

A drop-in replacement for the [Memoize](https://github.com/melpon/memoize) library using [Cachex](https://github.com/whitfin/cachex).

Provides the `defmemo` macro for easy function memoization with TTL support.

## Installation

Add `cachex_memoize` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:cachex_memoize, "~> 0.1.0"}
  ]
end
```

## Setup

1. Add a Cachex instance to your application supervision tree:

```elixir
# In lib/my_app/application.ex
children = [
  {Cachex, name: :my_cache},
  # ...
]
```

2. Configure the cache name (optional, defaults to `:cachex_memoize`):

```elixir
# In config/config.exs
config :cachex_memoize, :cache, :my_cache
```

## Usage

```elixir
defmodule MyModule do
  use CachexMemoize

  # Basic memoization with TTL (in milliseconds)
  defmemo get_user(id), expires_in: 60_000 do
    Repo.get!(User, id)
  end

  # With guards
  defmemo search(query) when is_binary(query), expires_in: 60_000 do
    do_search(query)
  end

  # Pattern matching
  defmemo fetch(""), expires_in: 60_000 do
    default_value()
  end

  defmemo fetch(key), expires_in: 60_000 do
    do_fetch(key)
  end

  # Default arguments
  defmemo list_items(page, limit \\ 20), expires_in: 60_000 do
    do_list(page, limit)
  end

  # No expiry (permanent cache)
  defmemo get_config(key) do
    load_config(key)
  end
end
```

### Using a specific cache

You can specify a cache name per module:

```elixir
defmodule MyModule do
  use CachexMemoize, cache: :my_specific_cache

  defmemo expensive_function(arg), expires_in: 60_000 do
    # ...
  end
end
```

## Cache Invalidation

```elixir
# Invalidate specific cached result
CachexMemoize.invalidate(MyModule, :get_user, [123])

# Invalidate all cached results for a function
CachexMemoize.invalidate(MyModule, :get_user)

# Invalidate all cached results for a module
CachexMemoize.invalidate(MyModule)

# Invalidate with specific cache
CachexMemoize.invalidate(MyModule, :get_user, [123], :my_cache)
```

## Migration from Memoize

Replace:

```elixir
use Memoize
```

With:

```elixir
use CachexMemoize
```

The `defmemo` macro is API-compatible with Memoize.

## License

MIT
