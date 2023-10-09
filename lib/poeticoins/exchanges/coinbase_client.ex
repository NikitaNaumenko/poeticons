defmodule Poeticoins.Exchanges.CoinbaseClient do
  alias Poeticoins.{Trade, Product}
  alias Poeticoins.Exchanges.Client
  require Client

  Client.defclient(
    exchange_name: "coinbase",
    host: ~c"ws-feed.exchange.coinbase.com",
    port: 443,
    currency_pairs: ["BTC-USD", "ETH-USD", "LTC-USD", "BTC-EUR", "ETH-EUR", "LTC-EUR"]
  )

  @behaviour Client

  # @impl Client
  # def exchange_name(), do: "coinbase"
  #
  # @impl Client
  # def server_host(), do: ~c"ws-feed.exchange.coinbase.com"
  #
  # @impl Client
  # def server_port(), do: 443

  @impl Client
  # def handle_ws_message(%{"type" => "ticker"} = msg, state) do
  #   _trade = message_to_trade(msg) |> IO.inspect(label: "coinbase")
  #   {:noreply, state}
  # end
  #
  # def handle_ws_message(msg, state) do
  #   IO.inspect(msg, label: "unhandled message")
  #   {:noreply, state}
  # end
  #
  @impl Client
  def subscription_frames(currency_pairs) do
    msg =
      %{
        "type" => "subscribe",
        "product_ids" => currency_pairs,
        "channels" => ["ticker"]
      }
      |> Jason.encode!()

    [{:text, msg}]
  end

  @spec message_to_trade(map()) :: {:ok, Trade.t()} | {:error, any()}
  def message_to_trade(msg) do
    with :ok <- validate_required(msg, ["product_id", "time", "price", "last_size"]),
         {:ok, traded_at, _} <- DateTime.from_iso8601(msg["time"]) do
      currency_pair = msg["product_id"]

      Trade.new(
        product: Product.new(exchange_name(), currency_pair),
        price: msg["price"],
        volume: msg["last_size"],
        traded_at: traded_at
      )
    else
      {:error, _reason} = error -> error
    end
  end
end