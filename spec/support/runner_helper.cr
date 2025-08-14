def consume_jobs(*, count : Int32 = 1, timeout : Time::Span = 10.seconds, &block : TJLavin::JobRun -> _)
  results = Channel(Exception?).new(count)

  array_to_hash = ->(array : Array(String)) : Hash(String, String) {
    hash = Hash(String, String).new
    (0...array.size).step(2) { |i| hash[array[i]] = array[i + 1] if array[i + 1]? }
    hash
  }

  AMQP::Client.start(TJLavin.configuration.amqp_url.to_s) do |c|
    c.channel do |ch|
      q = ch.queue(
        TJLavin.configuration.routing_key,
        args: AMQP::Client::Arguments.new({"x-max-priority": 255})
      )
      ch.prefetch(count: 1)

      tag = "spec-#{Random::Secure.hex(4)}"

      # Non-blocking subscribe; runs in a background fiber
      q.subscribe(no_ack: false, block: false, tag: tag) do |msg|
        ex = begin
          message = JSON.parse(msg.body_io.to_s)
          job_run = TJLavin::JobRun.new(message["class"].as_s)
          job_run.config = array_to_hash.call(message["args"].as_a.map(&.as_s))
          job_run.run

          block.call(job_run)

          nil
        rescue exc
          exc
        ensure
          ch.basic_ack(msg.delivery_tag)
        end

        # buffered, so this never blocks the subscriber fiber
        results.send(ex)
      end

      # Timeout guard
      timeout_ch = Channel(Nil).new
      spawn do
        sleep timeout
        timeout_ch.send(nil)
      end

      received = 0
      loop do
        select
        when ex = results.receive
          received += 1
          if ex
            q.unsubscribe(tag) rescue nil
            raise ex
          end
          break if received >= count
        when timeout_ch.receive
          q.unsubscribe(tag) rescue nil
          raise "Timeout waiting for #{count} AMQP message(s) after #{timeout}"
        end
      end

      q.unsubscribe(tag) rescue nil
    end
  end
end
