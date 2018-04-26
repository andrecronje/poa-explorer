defmodule Explorer.Market.MarketHistory.Cataloger do
  @moduledoc """
  Fetches the daily market history.
  """

  use GenServer

  require Logger

  alias Explorer.Market.MarketHistory
  alias Explorer.Repo

  @typep milliseconds :: non_neg_integer()

  ## GenServer callbacks

  @impl GenServer
  def init(:ok) do
    send(self(), {:fetch_history, 365})

    {:ok, %{}}
  end

  @impl GenServer
  def handle_info({:fetch_history, day_count}, state) do
    fetch_history(day_count)

    {:noreply, state}
  end

  @impl GenServer
  # Record fetch successful.
  def handle_info({_ref, {_, _, {:ok, records}}}, state) do
    bulk_insert_records(records)

    # Continually check history every hour
    Process.send_after(self(), {:fetch_history, 1}, :timer.minutes(60))

    {:noreply, state}
  end

  @impl GenServer
  # Failed to get records. Try again.
  def handle_info({_ref, {day_count, failed_attempts, :error}}, state) do
    Logger.warn(fn -> "Failed to fetch market history. Trying again." end)

    fetch_history(day_count, failed_attempts + 1)

    {:noreply, state}
  end

  # Callback that a monitored process has shutdown
  @impl GenServer
  def handle_info({:DOWN, _, :process, _, _}, state) do
    {:noreply, state}
  end

  @doc """
  Starts a process to continually fetch market history.
  """
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  ## Private Functions

  @spec bulk_insert_records([Source.record()]) :: term()
  defp bulk_insert_records(records) do
    Repo.insert_all(MarketHistory, records, on_conflict: :nothing, conflict_target: [:date])
  end

  @spec base_backoff :: milliseconds()
  defp base_backoff do
    config_or_default(:base_backoff, 100)
  end

  @spec config_or_default(atom(), term()) :: term()
  defp config_or_default(key, default) do
    Application.get_env(:explorer, __MODULE__, [])[key] || default
  end

  @spec source() :: module()
  defp source do
    config_or_default(:source, Explorer.Market.MarketHistory.Source.CryptoCompare)
  end

  @spec fetch_history(non_neg_integer(), non_neg_integer()) :: Task.t()
  defp fetch_history(day_count, failed_attempts \\ 0) do
    Task.Supervisor.async_nolink(Explorer.MarketTaskSupervisor, fn ->
      Process.sleep(delay(failed_attempts))
      {day_count, failed_attempts, source().fetch_history(day_count)}
    end)
  end

  @spec delay(non_neg_integer()) :: milliseconds()
  defp delay(0), do: 0
  defp delay(1), do: base_backoff()
  defp delay(failed_attempts) do
    # Simulates 2^n
    multiplier = Enum.reduce(2..failed_attempts, 1, fn (_, acc) -> 2 * acc end)
    multiplier * base_backoff()
  end
end
