import Config

export_dir =
  if Mix.env() == :test do
    System.tmp_dir!() <> "/websockex_nova_test_exports"
  else
    "exports/"
  end

config :websockex_nova, :export_dir, export_dir
