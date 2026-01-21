defmodule CachexMemoize do
  @moduledoc """
  A drop-in replacement for the Memoize library using Cachex.

  ## Setup

  1. Add a Cachex instance to your application supervision tree:

      ```elixir
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

  3. Use in your modules:

      ```elixir
      defmodule MyModule do
        use CachexMemoize

        defmemo expensive_function(arg), expires_in: 60_000 do
          # expensive computation
        end
      end
      ```

  ## Usage

  The `defmemo` macro supports several patterns:

      # Basic with TTL (milliseconds)
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
      defmemo list_items(page, limit \\\\ 20), expires_in: 60_000 do
        do_list(page, limit)
      end

      # No expiry (permanent cache)
      defmemo get_config(key) do
        load_config(key)
      end

  ## Invalidation

      # Invalidate specific cached result
      CachexMemoize.invalidate(MyModule, :get_user, [123])

      # Invalidate all cached results for a function
      CachexMemoize.invalidate(MyModule, :get_user)

      # Invalidate all cached results for a module
      CachexMemoize.invalidate(MyModule)
  """

  @default_cache :cachex_memoize

  defmacro __using__(opts) do
    cache = Keyword.get(opts, :cache)

    quote do
      import CachexMemoize, only: [defmemo: 2, defmemo: 3]
      @__cachex_memoize_cache__ unquote(cache)
    end
  end

  @doc """
  Defines a memoized function.

  ## Options

    * `:expires_in` - TTL in milliseconds. If not specified, the value is cached permanently.

  ## Examples

      defmemo my_function(arg1, arg2), expires_in: 60_000 do
        # expensive computation
      end

      defmemo permanent_cache(key) do
        # cached forever
      end
  """
  defmacro defmemo(call, opts_or_body)

  # Pattern: defmemo func(args) do ... end (no options)
  defmacro defmemo(call, do: body) do
    generate_memoized_function(call, [], body, __CALLER__)
  end

  # Pattern: defmemo func(args), expires_in: ... do ... end
  defmacro defmemo(call, opts) when is_list(opts) do
    {body, opts} = Keyword.pop!(opts, :do)
    generate_memoized_function(call, opts, body, __CALLER__)
  end

  # Pattern for multiline: defmemo func(args) when guard, opts do ... end
  defmacro defmemo(call, opts, do: body) do
    generate_memoized_function(call, opts, body, __CALLER__)
  end

  defp generate_memoized_function(call, opts, body, caller) do
    {name, args, guards} = extract_function_parts(call)
    # Support both :expires_in and :expires (Memoize uses both)
    expires_in = Keyword.get(opts, :expires_in) || Keyword.get(opts, :expires, :infinity)
    impl_name = impl_function_name(name)

    # Handle default arguments
    {args_without_defaults, default_defs} =
      generate_default_argument_handlers(name, args, guards, caller)

    # Generate the main wrapper and impl functions
    main_def =
      generate_wrapper_function(name, args_without_defaults, guards, expires_in, caller)

    impl_def = generate_impl_function(impl_name, args, guards, body)

    quote do
      unquote_splicing(default_defs)
      unquote(main_def)
      unquote(impl_def)
    end
  end

  defp extract_function_parts({:when, _, [call, guards]}) do
    {name, args} = extract_name_and_args(call)
    {name, args, guards}
  end

  defp extract_function_parts(call) do
    {name, args} = extract_name_and_args(call)
    {name, args, nil}
  end

  defp extract_name_and_args({name, _, nil}) when is_atom(name) do
    {name, []}
  end

  defp extract_name_and_args({name, _, args}) when is_atom(name) and is_list(args) do
    {name, args}
  end

  defp impl_function_name(name) do
    String.to_atom("__#{name}_impl")
  end

  defp generate_default_argument_handlers(name, args, guards, caller) do
    {args_with_defaults, _args_without_defaults} =
      Enum.split_with(args, fn
        {:\\, _, _} -> true
        _ -> false
      end)

    if Enum.empty?(args_with_defaults) do
      {args, []}
    else
      default_defs = generate_default_delegates(name, args, guards, caller)
      normalized_args = normalize_args_for_wrapper(args)
      {normalized_args, default_defs}
    end
  end

  defp generate_default_delegates(name, args, guards, _caller) do
    defaults_info =
      args
      |> Enum.with_index()
      |> Enum.filter(fn
        {{:\\, _, _}, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {{:\\, _, [_arg, default]}, idx} -> {idx, default} end)

    for i <- 1..length(defaults_info) do
      defaults_to_omit = Enum.take(defaults_info, i)
      omit_indices = Enum.map(defaults_to_omit, fn {idx, _} -> idx end)

      variant_args =
        args
        |> Enum.with_index()
        |> Enum.reject(fn {_, idx} -> idx in omit_indices end)
        |> Enum.map(fn {arg, _} -> strip_default(arg) end)

      full_args =
        args
        |> Enum.with_index()
        |> Enum.map(fn {arg, idx} ->
          case Enum.find(defaults_to_omit, fn {default_idx, _} -> default_idx == idx end) do
            {_, default_value} -> default_value
            nil -> strip_default(arg)
          end
        end)

      if guards do
        quote do
          def unquote(name)(unquote_splicing(variant_args)) when unquote(guards) do
            unquote(name)(unquote_splicing(full_args))
          end
        end
      else
        quote do
          def unquote(name)(unquote_splicing(variant_args)) do
            unquote(name)(unquote_splicing(full_args))
          end
        end
      end
    end
  end

  defp strip_default({:\\, _, [arg, _default]}), do: arg
  defp strip_default(arg), do: arg

  defp normalize_args_for_wrapper(args) do
    Enum.map(args, &strip_default/1)
  end

  defp transform_args_for_wrapper(args) do
    args
    |> Enum.with_index()
    |> Enum.map(fn {arg, idx} ->
      case arg do
        {name, _meta, context} when is_atom(name) and is_atom(context) and name != :_ ->
          {arg, arg}

        _ ->
          var = Macro.var(:"memoize_arg_#{idx}", nil)
          pattern = quote do: unquote(var) = unquote(arg)
          {pattern, var}
      end
    end)
    |> Enum.unzip()
  end

  defp generate_wrapper_function(name, args, guards, expires_in, caller) do
    impl_name = impl_function_name(name)
    {wrapper_args, call_args} = transform_args_for_wrapper(args)

    module = caller.module
    key_expr = build_cache_key_expr(module, name, call_args)

    commit_expr =
      if expires_in == :infinity do
        quote do
          {:commit, unquote(impl_name)(unquote_splicing(call_args))}
        end
      else
        quote do
          {:commit, unquote(impl_name)(unquote_splicing(call_args)), expire: unquote(expires_in)}
        end
      end

    cache_body =
      quote do
        cache = @__cachex_memoize_cache__ || CachexMemoize.default_cache()
        key = unquote(key_expr)

        case Cachex.fetch(cache, key, fn _key ->
               unquote(commit_expr)
             end) do
          {:ok, value} -> value
          {:commit, value} -> value
          {:commit, value, _opts} -> value
          {:error, reason} -> raise "CachexMemoize error: #{inspect(reason)}"
        end
      end

    if guards do
      quote do
        def unquote(name)(unquote_splicing(wrapper_args)) when unquote(guards) do
          unquote(cache_body)
        end
      end
    else
      quote do
        def unquote(name)(unquote_splicing(wrapper_args)) do
          unquote(cache_body)
        end
      end
    end
  end

  defp build_cache_key_expr(module, name, args) do
    quote do
      "memo:#{unquote(module)}:#{unquote(name)}:#{:erlang.phash2(unquote(args))}"
    end
  end

  defp generate_impl_function(impl_name, args, guards, body) do
    impl_args = Enum.map(args, &strip_default/1)

    if guards do
      quote do
        defp unquote(impl_name)(unquote_splicing(impl_args)) when unquote(guards) do
          unquote(body)
        end
      end
    else
      quote do
        defp unquote(impl_name)(unquote_splicing(impl_args)) do
          unquote(body)
        end
      end
    end
  end

  # --- Public API ---

  @doc """
  Returns the default cache name.

  Can be configured via:

      config :cachex_memoize, :cache, :my_cache

  Defaults to `:cachex_memoize`.
  """
  def default_cache do
    Application.get_env(:cachex_memoize, :cache, @default_cache)
  end

  @doc """
  Invalidate cached results.

  ## Examples

      # Invalidate all cached results for a module
      CachexMemoize.invalidate(MyModule)

      # Invalidate all cached results for a function
      CachexMemoize.invalidate(MyModule, :get_user)

      # Invalidate a specific cached result
      CachexMemoize.invalidate(MyModule, :get_user, [123])

      # Invalidate with a specific cache
      CachexMemoize.invalidate(:my_cache, MyModule)
      CachexMemoize.invalidate(:my_cache, MyModule, :get_user)
      CachexMemoize.invalidate(:my_cache, MyModule, :get_user, [123])
  """
  # invalidate/1 - Invalidate all cached results for a module
  def invalidate(module) when is_atom(module) do
    invalidate_module(default_cache(), module)
  end

  # invalidate/2 - Invalidate all for a function OR all for a module with specific cache
  def invalidate(module, function) when is_atom(module) and is_atom(function) do
    invalidate_function(default_cache(), module, function)
  end

  def invalidate(cache, module) when is_atom(cache) and is_atom(module) do
    invalidate_module(cache, module)
  end

  # invalidate/3 - Invalidate specific result OR all for function with specific cache
  def invalidate(module, function, args)
      when is_atom(module) and is_atom(function) and is_list(args) do
    key = build_cache_key(module, function, args)
    Cachex.del(default_cache(), key)
  end

  def invalidate(cache, module, function)
      when is_atom(cache) and is_atom(module) and is_atom(function) do
    invalidate_function(cache, module, function)
  end

  # invalidate/4 - Invalidate specific result with specific cache
  def invalidate(cache, module, function, args)
      when is_atom(cache) and is_atom(module) and is_atom(function) and is_list(args) do
    key = build_cache_key(module, function, args)
    Cachex.del(cache, key)
  end

  defp invalidate_function(cache, module, function) do
    prefix = "memo:#{module}:#{function}:"

    cache
    |> Cachex.stream!()
    |> Stream.filter(fn {:entry, key, _, _, _} ->
      is_binary(key) and String.starts_with?(key, prefix)
    end)
    |> Enum.each(fn {:entry, key, _, _, _} ->
      Cachex.del(cache, key)
    end)

    :ok
  end

  defp invalidate_module(cache, module) do
    prefix = "memo:#{module}:"

    cache
    |> Cachex.stream!()
    |> Stream.filter(fn {:entry, key, _, _, _} ->
      is_binary(key) and String.starts_with?(key, prefix)
    end)
    |> Enum.each(fn {:entry, key, _, _, _} ->
      Cachex.del(cache, key)
    end)

    :ok
  end

  defp build_cache_key(module, function, args) do
    "memo:#{module}:#{function}:#{:erlang.phash2(args)}"
  end
end
