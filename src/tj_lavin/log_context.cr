module TJLavin
  # Moves the configured `Log.context` keys across the queue: into AMQP
  # headers when a job is enqueued, and back into `Log.context` when the
  # runner picks the message up.
  module LogContext
    HEADER_PREFIX = "x-tjlavin-log-"

    def self.header_name(key : Symbol) : String
      "#{HEADER_PREFIX}#{key}"
    end

    def self.capture : Hash(String, String)
      headers = Hash(String, String).new
      metadata = ::Log.context.metadata

      TJLavin.configuration.propagate_log_context.each do |key|
        if value = metadata[key]?
          headers[header_name(key)] = value.to_s
        end
      end

      headers
    end

    def self.restore(headers : AMQ::Protocol::Table?) : Hash(Symbol, String)
      values = Hash(Symbol, String).new
      return values unless headers

      TJLavin.configuration.propagate_log_context.each do |key|
        if value = headers[header_name(key)]?.as?(String)
          values[key] = value
        end
      end

      values
    end

    def self.with_restored(headers : AMQ::Protocol::Table?, &)
      values = restore(headers)

      if values.empty?
        yield
      else
        ::Log.with_context(values) { yield }
      end
    end
  end
end
