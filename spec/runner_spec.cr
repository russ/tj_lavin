require "./spec_helper"

describe TJLavin::Runner do
  describe ".start with reconnection" do
    it "reconnects and continues processing after the AMQP connection is force-closed" do
      purge_queue("spec_reconnect")

      received = ::Channel(String).new(4)
      ReconnectWorkerHelper.callback = ->(name : String) {
        received.send(name) rescue nil
        nil
      }

      spawn name: "tjlavin-runner-spec" do
        TJLavin::Runner.start(["spec_reconnect"])
      end

      # Allow the runner to subscribe before producing.
      sleep 1.second

      ReconnectWorkerHelper::ReconnectWorker.new(name: "before-disconnect").enqueue

      first = wait_for_job(received, 10.seconds)
      first.should eq("before-disconnect")

      # Simulate CloudAMQP cycling the broker.
      ManagementClient.close_all_connections.should be > 0

      # Give the runner time to detect the close (heartbeat watchdog ticks
      # every second) and reconnect through the backoff.
      sleep 4.seconds

      ReconnectWorkerHelper::ReconnectWorker.new(name: "after-reconnect").enqueue

      second = wait_for_job(received, 15.seconds)
      second.should eq("after-reconnect")
    ensure
      ReconnectWorkerHelper.callback = nil
      TJLavin::Runner.stop
    end
  end

  describe ".connection_url" do
    it "appends the configured heartbeat when missing" do
      original = TJLavin.configuration.amqp_url
      begin
        TJLavin.configuration.amqp_url = "amqp://guest:guest@example.com:5672/"
        TJLavin.connection_url.should contain("heartbeat=#{TJLavin.configuration.heartbeat}")
      ensure
        TJLavin.configuration.amqp_url = original
      end
    end

    it "preserves an explicit heartbeat in the URL" do
      original = TJLavin.configuration.amqp_url
      begin
        TJLavin.configuration.amqp_url = "amqp://guest:guest@example.com:5672/?heartbeat=120"
        TJLavin.connection_url.should contain("heartbeat=120")
      ensure
        TJLavin.configuration.amqp_url = original
      end
    end
  end
end

private def purge_queue(name : String) : Nil
  AMQP::Client.start(TJLavin.connection_url) do |c|
    c.channel do |ch|
      q = ch.queue(name, args: AMQP::Client::Arguments.new({"x-max-priority": 255}))
      q.purge
    end
  end
rescue
  # Queue may not exist yet on a fresh broker — that's fine.
end

private def wait_for_job(channel : ::Channel(String), timeout : Time::Span) : String
  # Buffered so the timer fiber's `send` always completes, even if the job
  # arrived first and nobody is waiting on the timer branch.
  timer = ::Channel(Nil).new(1)
  spawn { sleep timeout; timer.send(nil) rescue nil }

  select
  when value = channel.receive
    value
  when timer.receive
    raise "Timeout waiting #{timeout} for runner to process a job"
  end
end
