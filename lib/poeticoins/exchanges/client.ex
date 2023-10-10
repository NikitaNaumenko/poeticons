defmodule Poeticoins.Exchanges.Client do
  use GenServer

  @type t() :: %__MODULE__{
          module: module(),
          conn: pid(),
          conn_ref: reference(),
          ws_ref: reference(),
          currency_pairs: [String.t()]
        }

  @callback exchange_name() :: string()
  @callback server_host() :: list()
  @callback server_port() :: integer()
  @callback subscription_frames([String.t()]) :: [{:text, String.t()}]
  @callback handle_ws_message(map(), any()) :: any()

  defstruct [:module, :conn, :conn_ref, :currency_pairs, :ws_ref]

  defmacro defclient(options) do
    exchange_name = Keyword.fetch!(options, :exchange_name)
    host = Keyword.fetch!(options, :host)
    port = Keyword.fetch!(options, :port)
    currency_pairs = Keyword.fetch!(options, :currency_pairs)
    client_module = __MODULE__

    quote do
      @behaviour unquote(client_module)
      import unquote(client_module), only: [validate_required: 2]
      require Logger
      def available_currency_pairs(), do: unquote(currency_pairs)
      def exchange_name(), do: unquote(exchange_name)
      def server_host(), do: unquote(host)
      def server_port(), do: unquote(port)

      def handle_ws_message(msg, state) do
        Logger.debug("Handle ws message: #{inspect(msg)}")
        {:noreply, state}
      end

      defoverridable handle_ws_message: 2
    end
  end

  def start_link(module, currency_pairs, opts \\ []) do
    GenServer.start_link(__MODULE__, {module, currency_pairs}, opts)
  end

  def init({module, currency_pairs}) do
    client = %__MODULE__{
      module: module,
      currency_pairs: currency_pairs
    }

    {:ok, client, {:continue, :connect}}
  end

  def handle_continue(:connect, client) do
    opts = server_opts()
    host = server_host(client.module)
    port = server_port(client.module)
    {:ok, conn} = :gun.open(host, port, opts)
    conn_ref = Process.monitor(conn)
    {:noreply, %{client | conn: conn, conn_ref: conn_ref}}
  end

  def handle_info({:gun_up, conn, :http}, %{conn: conn} = client) do
    ref = :gun.ws_upgrade(conn, "/")
    {:noreply, %{client | ws_ref: ref}}
  end

  def handle_info({:gun_upgrade, conn, _ref, ["websocket"], _headers}, %{conn: conn} = client) do
    subscribe(client)
    {:noreply, client}
  end

  def handle_info({:gun_ws, conn, _ref, {:text, msg} = _frame}, %{conn: conn} = client) do
    handle_ws_message(Jason.decode!(msg), client)
  end

  def subscribe(client) do
    subscription_frames(client.module, client.currency_pairs)
    |> Enum.each(&:gun.ws_send(client.conn, client.ws_ref, &1))
  end

  @spec validate_required(map(), [String.t()]) :: :ok | {:error, {String.t(), :required}}
  def validate_required(msg, keys) do
    required_key = Enum.find(keys, fn k -> is_nil(msg[k]) end)
    if is_nil(required_key), do: :ok, else: {:error, {required_key, :required}}
  end

  defp subscription_frames(module, currency_pairs) do
    module.subscription_frames(currency_pairs)
  end

  defp handle_ws_message(msg, client) do
    module = client.module
    apply(module, :handle_ws_message, [msg, client])
  end

  defp server_port(module), do: apply(module, :server_port, [])
  defp server_host(module), do: apply(module, :server_host, [])

  defp server_opts() do
    %{
      connect_timeout: 60000,
      retry: 10,
      retry_timeout: 300,
      transport: :tls,
      tls_opts: [
        verify: :verify_none,
        # Specify a bunch of certs
        # cacerts: :certifi.cacerts(),
        # Or just one cert
        # cacertfile: CAStore.file_path(),
        depth: 99,
        reuse_sessions: false
      ],
      # See above explanation why you should specify
      http_opts: %{version: :"HTTP/1.1"},
      protocols: [:http]
    }
  end
end
