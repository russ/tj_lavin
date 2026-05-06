module TJLavin
  class Runner
    @@stop_requested = false

    # Signal a running `Runner.start` loop to exit after the current
    # connection cycle completes. Intended for tests and graceful shutdown.
    def self.stop : Nil
      @@stop_requested = true
    end

    def self.start(queues : Array(String)? = nil)
      Log.notice { "TJ Lavin is pedalin'..." }

      queue_names = queues || Base.queues.to_a
      queue_names << TJLavin.configuration.routing_key if queue_names.empty?

      backoff = TJLavin.configuration.reconnect_backoff
      max_backoff = TJLavin.configuration.reconnect_backoff_max

      loop do
        break if @@stop_requested

        begin
          run_once(queue_names)
          backoff = TJLavin.configuration.reconnect_backoff
        rescue ex
          Log.error(exception: ex) do
            "TJLavin connection error; reconnecting in #{backoff.total_seconds.to_i}s"
          end
        end

        break if @@stop_requested

        sleep backoff
        backoff = backoff * 2
        backoff = max_backoff if backoff > max_backoff
      end
    ensure
      @@stop_requested = false
    end

    private def self.run_once(queue_names : Array(String))
      shutdown = ::Channel(Nil).new(1)

      AMQP::Client.start(TJLavin.connection_url) do |c|
        c.on_close do |code, reason|
          Log.warn { "AMQP connection closed by server (#{code}): #{reason}" }
          shutdown.send(nil) rescue nil
        end

        c.channel do |ch|
          ch.on_close do |code, reason|
            Log.warn { "AMQP channel closed by server (#{code}): #{reason}" }
            shutdown.send(nil) rescue nil
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
            until c.closed? || ch.closed? || @@stop_requested
              sleep 1.second
            end
            shutdown.send(nil) rescue nil
          end

          shutdown.receive
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
