module TJLavin
  class Runner
    def self.start(queues : Array(String)? = nil)
      Log.notice { "TJ Lavin is pedalin'..." }

      queue_names = queues || Base.queues.to_a
      queue_names << TJLavin.configuration.routing_key if queue_names.empty?

      array_to_hash = ->(array : Array(String)) : Hash(String, String) {
        hash = Hash(String, String).new

        (0...array.size).step(2) do |index|
          hash[array[index]] = array[index + 1] if array[index + 1]
        end

        hash
      }

      AMQP::Client.start(TJLavin.configuration.amqp_url.to_s) do |c|
        c.channel do |ch|
          ch.prefetch(count: 1)

          queue_names.each do |queue_name|
            q = ch.queue(queue_name, args: AMQP::Client::Arguments.new({"x-max-priority": 255}))

            Log.notice { "Subscribing to queue: #{queue_name}" }

            q.subscribe(no_ack: false, block: false) do |msg|
              Log.notice { "Received: #{msg.body_io}" }

              message = JSON.parse(msg.body_io.to_s)

              job_run = JobRun.new(message["class"].as_s)
              job_run.config = array_to_hash.call(message["args"].as_a.map(&.as_s))
              job_instance = job_run.run

              if job_instance.exception
                ch.basic_reject(msg.delivery_tag, requeue: false)
              else
                ch.basic_ack(msg.delivery_tag)
              end

              Log.notice { "Done" }
            rescue e
              Log.notice { "Error: #{e.message}".colorize(:red) }
              ch.basic_reject(msg.delivery_tag, requeue: false)
            end
          end

          Log.notice { "Waiting for tasks on #{queue_names.join(", ")}. To exit press CTRL+C" }

          # Block the main fiber to keep the process alive
          Channel(Nil).new.receive
        end
      end
    end
  end
end
