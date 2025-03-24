module TJLavin
  class Runner
    def self.start(routing_key : String)
      Log.notice { "TJ Lavin is pedalin'..." }

      array_to_hash = ->(array : Array(String)) : Hash(String, String) {
        hash = Hash(String, String).new

        (0...array.size).step(2) do |index|
          hash[array[index]] = array[index + 1] if array[index + 1]
        end

        hash
      }

      AMQP::Client.start(TJLavin.configuration.amqp_url.to_s) do |c|
        c.channel do |ch|
          q = ch.queue(routing_key, args: AMQP::Client::Arguments.new({"x-max-priority": 255}))
          ch.prefetch(count: 1)

          puts "Waiting for tasks. To exit press CTRL+C"

          q.subscribe(no_ack: false, block: true) do |msg|
            Log.notice { "Received: #{msg.body_io.to_s}" }

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
            pp! e
          end
        end
      end
    end
  end
end
