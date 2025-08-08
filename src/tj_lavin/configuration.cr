module TJLavin
  class_getter configuration = Configuration.new

  def self.configure(&) : Nil
    yield configuration
  end

  class Configuration
    property amqp_url : String?
    property routing_key : String = "tjlavin"
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
end
