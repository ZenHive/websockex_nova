import Config

export_dir =
  if Mix.env() == :test do
    System.tmp_dir!() <> "/websockex_nova_test_exports"
  else
    "exports/"
  end

# config :websockex_nova, SlipstreamClient, uri: "ws://test.deribit.com:8080/api/v2/"
config :websockex_nova, Deribit,
  client_id: System.fetch_env!("DERIBIT_CLIENT_ID"),
  client_secret: System.fetch_env!("DERIBIT_CLIENT_SECRET")
