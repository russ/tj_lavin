module TJLavin
  class_getter configuration = Configuration.new

  def self.configure(&) : Nil
    yield configuration
  end

  class Configuration
    property amqp_url : String?
    property default_exchange : String = "" # Empty string for default exchange
    property delayed_exchange : String = "tjlavin.delayed"
    property routing_key : String = "tjlavin"

    # Seconds between AMQP heartbeats. The server pings the client at this
    # interval; if two intervals pass with no traffic, the underlying TCP
    # socket is closed. This is what catches half-open connections after a
    # broker upgrade or network drop. Set to 0 to disable.
    property heartbeat : Int32 = 30

    # Initial wait between reconnect attempts. Doubles up to `reconnect_backoff_max`.
    property reconnect_backoff : Time::Span = 1.second
    property reconnect_backoff_max : Time::Span = 30.seconds

    property? validated = false

    def validate
      return if validated?
      validated = true

      unless [amqp_url].compact_map.empty?
        message = <<-error
        TJLavin cannot start because the amqp connection string hasn't been provided.

        For example, in your application config:

        TJLavin.configure do |settings|
          settings.amqp_url = (ENV["AMQP_TLS_URL"]? || ENV["AMQP_URL"]? || "amqps://guest:guest@localhost")
          settings.routing_key = ENV["AMQP_ROUTING_KEY"]? # default is "tjlavin"
        end

        error

        raise message
      end
    end
  end

  def self.connection_url : String
    raw = configuration.amqp_url
    raise "TJLavin.configuration.amqp_url is not set" if raw.nil? || raw.empty?

    uri = URI.parse(raw)
    params = uri.query_params
    unless params.has_key?("heartbeat")
      params["heartbeat"] = configuration.heartbeat.to_s
      uri.query = params.to_s
    end
    uri.to_s
  end
end
