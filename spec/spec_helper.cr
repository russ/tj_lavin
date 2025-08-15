require "log"

Log.setup_from_env(default_level: :error)

Signal::SEGV.reset # Let the OS generate a coredump

require "spec"
require "../src/tj_lavin"
require "./support/*"

TJLavin.configure do |settings|
  settings.amqp_url = ENV["AMQP_URL"]? || "amqp://guest:guest@localhost:5672"
end
