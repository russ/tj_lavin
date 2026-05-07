module TJLavin
  class Runner
    @@stop_requested = Atomic(UInt8).new(0_u8)

    # Signal a running `Runner.start` loop to exit after the current
    # connection cycle completes. Intended for tests and graceful shutdown.
    def self.stop : Nil
      @@stop_requested.set(1_u8)
    end

    private def self.stop_requested? : Bool
      @@stop_requested.get == 1_u8
    end

    def self.start(queues : Array(String)? = nil)
      Log.notice { "TJ Lavin is pedalin'..." }

      queue_names = queues || Base.queues.to_a
      queue_names << TJLavin.configuration.routing_key if queue_names.empty?

      backoff = TJLavin.configuration.reconnect_backoff
      max_backoff = TJLavin.configuration.reconnect_backoff_max

      loop do
        break if stop_requested?

        begin
          run_once(queue_names)
          backoff = TJLavin.configuration.reconnect_backoff
        rescue ex : IO::Error | OpenSSL::Error | AMQP::Client::Error
          Log.error(exception: ex) do
            "TJLavin connection error; reconnecting in #{backoff.total_seconds.to_i}s"
          end
        end

        interruptible_sleep(backoff)
        backoff = backoff * 2
        backoff = max_backoff if backoff > max_backoff
      end
    ensure
      @@stop_requested.set(0_u8)
    end

    # Sleep that returns early if `Runner.stop` is called. Polls in 1s
    # increments so the longest reconnect backoff still tears down within
    # ~1s of a stop request — important for test cleanup and graceful
    # shutdown.
    private def self.interruptible_sleep(duration : Time::Span) : Nil
      return if duration <= 0.seconds
      deadline = Time.monotonic + duration
      loop do
        return if stop_requested?
        remaining = deadline - Time.monotonic
        return if remaining <= 0.seconds
        step = remaining > 1.second ? 1.second : remaining
        sleep step
      end
    end

    private def self.run_once(queue_names : Array(String))
      # Multiple sources race to signal shutdown (server-side connection
      # close, channel close, watchdog). `Channel#close` is idempotent and
      # non-blocking, so they can all fire without parking each other —
      # `send` would block once a receiver picked up the first value.
      shutdown = ::Channel(Nil).new

      AMQP::Client.start(TJLavin.connection_url) do |c|
        c.on_close do |code, reason|
          Log.warn { "AMQP connection closed by server (#{code}): #{reason}" }
          shutdown.close rescue nil
        end

        c.channel do |ch|
          ch.on_close do |code, reason|
            Log.warn { "AMQP channel closed by server (#{code}): #{reason}" }
            shutdown.close rescue nil
          end

          ch.prefetch(count: 1)

          queue_names.each do |queue_name|
            subscribe_to_queue(ch, queue_name)
          end

          Log.notice { "Waiting for tasks on #{queue_names.join(", ")}. To exit press CTRL+C" }

          # Watchdog catches unclean disconnects (TCP drop, missed heartbeat)
          # where amqp-client's read_loop exits via IO::Error without firing
          # `on_close`. Without this the main fiber would park forever on a
          # dead connection.
          spawn name: "tjlavin-watchdog" do
            until c.closed? || ch.closed? || stop_requested?
              sleep 1.second
            end
            shutdown.close rescue nil
          end

          shutdown.receive rescue nil
        end
      end
    end

    private def self.subscribe_to_queue(ch, queue_name : String)
      q = ch.queue(queue_name, args: AMQP::Client::Arguments.new({"x-max-priority": 255}))

      Log.notice { "Subscribing to queue: #{queue_name}" }

      q.subscribe(no_ack: false, block: false) do |msg|
        body = msg.body_io.to_s
        Log.notice { "Received: #{body}" }

        message = JSON.parse(body)
        job_class = message["class"].as_s

        started_at = Time.monotonic
        job_run = JobRun.new(job_class)
        job_run.config = array_to_hash(message["args"].as_a.map(&.as_s))
        job_instance = job_run.run
        duration_ms = (Time.monotonic - started_at).total_milliseconds.to_i64

        if job_instance.exception
          ch.basic_reject(msg.delivery_tag, requeue: false)
          Log.with_context(class: job_class, duration_ms: duration_ms) do
            Log.notice { "Failed" }
          end
        else
          ch.basic_ack(msg.delivery_tag)
          Log.with_context(class: job_class, duration_ms: duration_ms) do
            Log.notice { "Done" }
          end
        end
      rescue e
        Log.notice { "Error: #{e.message}".colorize(:red) }
        ch.basic_reject(msg.delivery_tag, requeue: false) rescue nil
      end
    end

    private def self.array_to_hash(array : Array(String)) : Hash(String, String)
      hash = Hash(String, String).new
      (0...array.size).step(2) do |index|
        hash[array[index]] = array[index + 1] if array[index + 1]?
      end
      hash
    end
  end
end
