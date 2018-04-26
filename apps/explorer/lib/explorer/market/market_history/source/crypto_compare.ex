defmodule Explorer.Market.MarketHistory.Source.CryptoCompare do
  @moduledoc """
  Adapter for fetching market history from https://cryptocompare.com.
  """

  alias Explorer.Market.MarketHistory.Source
  alias HTTPoison.Response

  @behaviour Source

  @typep unix_timestamp :: non_neg_integer()

  @impl Source
  def fetch_history(previous_days) do
    url = history_url(previous_days)
    headers = [{"Content-Type", "application/json"}]

    case HTTPoison.get(url, headers) do
      {:ok, %Response{body: body, status_code: 200}} ->
        {:ok, format_data(body)}

      _ ->
        :error
    end
  end

  @spec base_url :: String.t()
  defp base_url do
    configured_url = Application.get_env(:explorer, __MODULE__, [])[:base_url]
    configured_url || "https://min-api.cryptocompare.com"
  end

  @spec date(unix_timestamp()) :: Date.t()
  defp date(unix_timestamp) do
    unix_timestamp
    |> DateTime.from_unix!()
    |> DateTime.to_date()
  end

  @spec format_data(String.t()) :: [Source.record()]
  defp format_data(data) do
    json = Jason.decode!(data)

    for item <- json["Data"] do
      %{
        closing_price: Decimal.new(item["close"]),
        date: date(item["time"]),
        opening_price: Decimal.new(item["open"])
      }
    end
  end

  @spec history_url(non_neg_integer()) :: String.t()
  defp history_url(previous_days) do
    # TODO fetch the configured token instead of BTC
    query_params = %{
      "fsym" => "BTC",
      "limit" => previous_days,
      "tsym" => "USD",
    }
    "#{base_url()}/data/histoday?#{URI.encode_query(query_params)}"
  end
end
