defmodule WebsockexNova.Transport.ReconnectionTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Transport.Reconnection
  alias WebsockexNova.Transport.Reconnection.ExponentialBackoff
  alias WebsockexNova.Transport.Reconnection.JitteredBackoff
  alias WebsockexNova.Transport.Reconnection.LinearBackoff

  describe "LinearBackoff strategy" do
    test "returns constant delay regardless of attempt number" do
      strategy = %LinearBackoff{delay: 1000}

      assert LinearBackoff.calculate_delay(strategy, 1) == 1000
      assert LinearBackoff.calculate_delay(strategy, 2) == 1000
      assert LinearBackoff.calculate_delay(strategy, 10) == 1000
    end

    test "uses default delay when not specified" do
      strategy = %LinearBackoff{}

      assert LinearBackoff.calculate_delay(strategy, 1) > 0
    end

    test "respects max retry limit" do
      strategy = %LinearBackoff{max_retries: 3}

      assert LinearBackoff.should_retry?(strategy, 1) == true
      assert LinearBackoff.should_retry?(strategy, 3) == true
      assert LinearBackoff.should_retry?(strategy, 4) == false
    end

    test "unlimited retries with :infinity" do
      strategy = %LinearBackoff{max_retries: :infinity}

      assert LinearBackoff.should_retry?(strategy, 1) == true
      assert LinearBackoff.should_retry?(strategy, 100) == true
      assert LinearBackoff.should_retry?(strategy, 1000) == true
    end
  end

  describe "ExponentialBackoff strategy" do
    test "increases delay exponentially with attempt number" do
      strategy = %ExponentialBackoff{initial_delay: 100}

      delay1 = ExponentialBackoff.calculate_delay(strategy, 1)
      delay2 = ExponentialBackoff.calculate_delay(strategy, 2)
      delay3 = ExponentialBackoff.calculate_delay(strategy, 3)

      # Initial delay is always the base value
      assert delay1 == 100

      # Should be exactly doubled each time (in test mode)
      # 100 * 2^1
      assert delay2 == 200
      # 100 * 2^2
      assert delay3 == 400
    end

    test "respects max delay" do
      strategy = %ExponentialBackoff{initial_delay: 100, max_delay: 500}

      # At attempt 5, raw delay would be 1600 (100 * 2^4), but capped at 500
      delay = ExponentialBackoff.calculate_delay(strategy, 5)
      assert delay == 500
    end

    test "respects max retry limit" do
      strategy = %ExponentialBackoff{max_retries: 5}

      assert ExponentialBackoff.should_retry?(strategy, 1) == true
      assert ExponentialBackoff.should_retry?(strategy, 5) == true
      assert ExponentialBackoff.should_retry?(strategy, 6) == false
    end

    test "unlimited retries with :infinity" do
      strategy = %ExponentialBackoff{max_retries: :infinity}

      assert ExponentialBackoff.should_retry?(strategy, 1) == true
      assert ExponentialBackoff.should_retry?(strategy, 100) == true
    end
  end

  describe "JitteredBackoff strategy" do
    test "increases delay linearly with jitter" do
      strategy = %JitteredBackoff{base_delay: 100, jitter_factor: 0.25}

      # Call multiple times to test for jitter range
      delays_attempt1 = for _ <- 1..10, do: JitteredBackoff.calculate_delay(strategy, 1)
      delays_attempt2 = for _ <- 1..10, do: JitteredBackoff.calculate_delay(strategy, 2)

      # First attempt: base_delay (100) with jitter
      Enum.each(delays_attempt1, fn delay ->
        # base ± 25%
        assert delay >= 75 && delay <= 125
      end)

      # Second attempt: base_delay * attempt (200) with jitter
      Enum.each(delays_attempt2, fn delay ->
        # base*2 ± 25%
        assert delay >= 150 && delay <= 250
      end)

      # Verify we get different values due to jitter
      assert length(Enum.uniq(delays_attempt1)) > 1
    end

    test "respects max retry limit" do
      strategy = %JitteredBackoff{max_retries: 4}

      assert JitteredBackoff.should_retry?(strategy, 1) == true
      assert JitteredBackoff.should_retry?(strategy, 4) == true
      assert JitteredBackoff.should_retry?(strategy, 5) == false
    end
  end

  describe "Reconnection module functions" do
    test "get_strategy returns the corresponding strategy" do
      assert %LinearBackoff{} = Reconnection.get_strategy(:linear)
      assert %ExponentialBackoff{} = Reconnection.get_strategy(:exponential)
      assert %JitteredBackoff{} = Reconnection.get_strategy(:jittered)
    end

    test "get_strategy accepts custom options" do
      strategy = Reconnection.get_strategy(:linear, max_retries: 10, delay: 2000)
      assert %LinearBackoff{max_retries: 10, delay: 2000} = strategy
    end

    test "calculate_delay delegates to the appropriate strategy" do
      linear = Reconnection.get_strategy(:linear, delay: 1000)
      exponential = Reconnection.get_strategy(:exponential, initial_delay: 100)

      assert Reconnection.calculate_delay(linear, 1) == 1000
      assert Reconnection.calculate_delay(linear, 2) == 1000

      # In test mode we have deterministic values without jitter
      assert Reconnection.calculate_delay(exponential, 1) == 100
      assert Reconnection.calculate_delay(exponential, 2) == 200
    end

    test "should_retry? delegates to the appropriate strategy" do
      limited = Reconnection.get_strategy(:linear, max_retries: 3)
      unlimited = Reconnection.get_strategy(:exponential, max_retries: :infinity)

      assert Reconnection.should_retry?(limited, 3) == true
      assert Reconnection.should_retry?(limited, 4) == false

      assert Reconnection.should_retry?(unlimited, 100) == true
    end
  end
end
