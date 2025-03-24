module TJLavin
  class_getter configuration = Configuration.new

  def self.configure(&block) : Nil
    yield configuration
  end

  class Configuration
    property amqp_url : String?
    property topic_name : String = "topicname"
    property validated = false

    def validate
      return if @validated
      @validated = true

      unless [amqp_url, topic_name].compact_map.empty?
        message = <<-error
        TJLavin cannot start because the amqp connection string hasn't been provided.

        For example, in your application config:

        TJLavin.configure do |settings|
          settings.amqp_url = (ENV["AMQP_TLS_URL"]? || ENV["AMQP_URL"]? || "amqps://guest:guest@localhost")
          settings.topic_name = (ENV["AMQP_TOPIC_NAME"]? || "hello")
        end

        error

        raise message
      end
    end
  end
end
