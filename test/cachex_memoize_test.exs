defmodule CachexMemoizeTest do
  use ExUnit.Case, async: false

  # Test module with various defmemo patterns
  defmodule TestMemoized do
    use CachexMemoize

    # Track call counts for testing
    def get_call_count(key) do
      Agent.get(__MODULE__.CallCounter, fn map -> Map.get(map, key, 0) end)
    end

    def reset_call_counts do
      Agent.update(__MODULE__.CallCounter, fn _ -> %{} end)
    end

    defp increment_call_count(key) do
      Agent.update(__MODULE__.CallCounter, fn map ->
        Map.update(map, key, 1, &(&1 + 1))
      end)
    end

    # Basic memoization with expires_in
    defmemo basic_func(value), expires_in: 60_000 do
      increment_call_count(:basic_func)
      value * 2
    end

    # No expires_in (permanent)
    defmemo permanent_func(value) do
      increment_call_count(:permanent_func)
      value + 10
    end

    # With guards
    defmemo guarded_func(value) when is_integer(value), expires_in: 60_000 do
      increment_call_count(:guarded_func)
      value * 3
    end

    # Pattern matching - empty string
    defmemo pattern_func(""), expires_in: 60_000 do
      increment_call_count(:pattern_func_empty)
      "empty"
    end

    # Pattern matching - non-empty string
    defmemo pattern_func(value) when is_binary(value), expires_in: 60_000 do
      increment_call_count(:pattern_func_string)
      "string: #{value}"
    end

    # Multiple arguments
    defmemo multi_arg_func(a, b, c), expires_in: 60_000 do
      increment_call_count(:multi_arg_func)
      a + b + c
    end

    # Default arguments
    defmemo default_arg_func(a, b \\ 10), expires_in: 60_000 do
      increment_call_count(:default_arg_func)
      a + b
    end

    # No arguments
    defmemo no_arg_func(), expires_in: 60_000 do
      increment_call_count(:no_arg_func)
      42
    end

    # Short TTL for expiration testing (200ms)
    defmemo short_ttl_func(value), expires_in: 200 do
      increment_call_count(:short_ttl_func)
      value
    end
  end

  setup_all do
    {:ok, _} = Agent.start_link(fn -> %{} end, name: TestMemoized.CallCounter)
    :ok
  end

  setup do
    TestMemoized.reset_call_counts()
    clear_test_cache()
    :ok
  end

  defp clear_test_cache do
    :cachex_memoize
    |> Cachex.stream!()
    |> Stream.filter(fn {:entry, key, _, _, _} ->
      is_binary(key) and String.starts_with?(key, "memo:")
    end)
    |> Enum.each(fn {:entry, key, _, _, _} ->
      Cachex.del(:cachex_memoize, key)
    end)
  end

  describe "basic memoization" do
    test "caches results for same arguments" do
      assert TestMemoized.basic_func(5) == 10
      assert TestMemoized.basic_func(5) == 10
      assert TestMemoized.basic_func(5) == 10

      assert TestMemoized.get_call_count(:basic_func) == 1
    end

    test "caches separately for different arguments" do
      assert TestMemoized.basic_func(5) == 10
      assert TestMemoized.basic_func(10) == 20
      assert TestMemoized.basic_func(5) == 10

      assert TestMemoized.get_call_count(:basic_func) == 2
    end
  end

  describe "permanent memoization (no expires_in)" do
    test "caches results permanently" do
      assert TestMemoized.permanent_func(5) == 15
      assert TestMemoized.permanent_func(5) == 15

      assert TestMemoized.get_call_count(:permanent_func) == 1
    end
  end

  describe "with guards" do
    test "respects guards and caches correctly" do
      assert TestMemoized.guarded_func(5) == 15
      assert TestMemoized.guarded_func(5) == 15

      assert TestMemoized.get_call_count(:guarded_func) == 1
    end
  end

  describe "pattern matching" do
    test "handles empty string pattern" do
      assert TestMemoized.pattern_func("") == "empty"
      assert TestMemoized.pattern_func("") == "empty"

      assert TestMemoized.get_call_count(:pattern_func_empty) == 1
    end

    test "handles non-empty string pattern" do
      assert TestMemoized.pattern_func("hello") == "string: hello"
      assert TestMemoized.pattern_func("hello") == "string: hello"

      assert TestMemoized.get_call_count(:pattern_func_string) == 1
    end

    test "different patterns cache separately" do
      assert TestMemoized.pattern_func("") == "empty"
      assert TestMemoized.pattern_func("hello") == "string: hello"

      assert TestMemoized.get_call_count(:pattern_func_empty) == 1
      assert TestMemoized.get_call_count(:pattern_func_string) == 1
    end
  end

  describe "multiple arguments" do
    test "caches based on all arguments" do
      assert TestMemoized.multi_arg_func(1, 2, 3) == 6
      assert TestMemoized.multi_arg_func(1, 2, 3) == 6

      assert TestMemoized.get_call_count(:multi_arg_func) == 1
    end

    test "different argument combinations cache separately" do
      assert TestMemoized.multi_arg_func(1, 2, 3) == 6
      assert TestMemoized.multi_arg_func(1, 2, 4) == 7

      assert TestMemoized.get_call_count(:multi_arg_func) == 2
    end
  end

  describe "default arguments" do
    test "works with default argument" do
      assert TestMemoized.default_arg_func(5) == 15
      assert TestMemoized.default_arg_func(5) == 15

      assert TestMemoized.get_call_count(:default_arg_func) == 1
    end

    test "works with explicit argument overriding default" do
      assert TestMemoized.default_arg_func(5, 20) == 25
      assert TestMemoized.default_arg_func(5, 20) == 25

      assert TestMemoized.get_call_count(:default_arg_func) == 1
    end

    test "default and explicit are cached together when equivalent" do
      assert TestMemoized.default_arg_func(5) == 15
      assert TestMemoized.default_arg_func(5, 10) == 15

      # Both calls use the same cache entry (5, 10)
      assert TestMemoized.get_call_count(:default_arg_func) == 1

      # Different second arg creates a new cache entry
      assert TestMemoized.default_arg_func(5, 20) == 25
      assert TestMemoized.get_call_count(:default_arg_func) == 2
    end
  end

  describe "no arguments" do
    test "caches function with no arguments" do
      assert TestMemoized.no_arg_func() == 42
      assert TestMemoized.no_arg_func() == 42

      assert TestMemoized.get_call_count(:no_arg_func) == 1
    end
  end

  describe "TTL expiration" do
    test "expires after TTL" do
      assert TestMemoized.short_ttl_func("test") == "test"
      assert TestMemoized.get_call_count(:short_ttl_func) == 1

      # Wait for expiration (200ms TTL + generous buffer)
      Process.sleep(1000)

      assert TestMemoized.short_ttl_func("test") == "test"
      assert TestMemoized.get_call_count(:short_ttl_func) == 2
    end
  end

  describe "invalidation" do
    test "invalidate/3 invalidates specific cached result" do
      assert TestMemoized.basic_func(5) == 10
      assert TestMemoized.get_call_count(:basic_func) == 1

      CachexMemoize.invalidate(TestMemoized, :basic_func, [5])

      assert TestMemoized.basic_func(5) == 10
      assert TestMemoized.get_call_count(:basic_func) == 2
    end

    test "invalidate/2 invalidates all cached results for a function" do
      assert TestMemoized.basic_func(5) == 10
      assert TestMemoized.basic_func(10) == 20
      assert TestMemoized.get_call_count(:basic_func) == 2

      CachexMemoize.invalidate(TestMemoized, :basic_func)

      assert TestMemoized.basic_func(5) == 10
      assert TestMemoized.basic_func(10) == 20
      assert TestMemoized.get_call_count(:basic_func) == 4
    end

    test "invalidate/1 invalidates all cached results for a module" do
      assert TestMemoized.basic_func(5) == 10
      assert TestMemoized.permanent_func(5) == 15
      assert TestMemoized.get_call_count(:basic_func) == 1
      assert TestMemoized.get_call_count(:permanent_func) == 1

      CachexMemoize.invalidate(TestMemoized)

      assert TestMemoized.basic_func(5) == 10
      assert TestMemoized.permanent_func(5) == 15
      assert TestMemoized.get_call_count(:basic_func) == 2
      assert TestMemoized.get_call_count(:permanent_func) == 2
    end
  end
end
