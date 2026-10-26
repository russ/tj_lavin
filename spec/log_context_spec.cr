require "./spec_helper"
require "log/spec"

describe TJLavin::LogContext do
  it "propagates nothing by default" do
    TJLavin::Configuration.new.propagate_log_context.should be_empty
  end

  describe "enqueue" do
    it "sends allowlisted context values as headers" do
      with_propagated([:request_id]) do
        purge_log_context_queue

        Log.with_context(request_id: "req-123", user_id: "user-1") do
          LogContextWorkerHelper::LogContextWorker.new(name: "a").enqueue
        end

        headers = fetch_log_context_headers
        headers["x-tjlavin-log-request_id"]?.should eq("req-123")
        headers["x-tjlavin-log-user_id"]?.should be_nil
      end
    end

    it "sends no headers when the key is not in the context" do
      with_propagated([:request_id]) do
        purge_log_context_queue

        LogContextWorkerHelper::LogContextWorker.new(name: "a").enqueue

        fetch_log_context_headers.should be_empty
      end
    end

    it "sends no headers when nothing is allowlisted" do
      purge_log_context_queue

      Log.with_context(request_id: "req-123") do
        LogContextWorkerHelper::LogContextWorker.new(name: "a").enqueue
      end

      fetch_log_context_headers.should be_empty
    end
  end

  describe "runner" do
    it "restores the context around the job and its runner log lines" do
      with_propagated([:request_id]) do
        Log.capture("tj_lavin") do |logs|
          seen = run_log_context_job { Log.with_context(request_id: "req-456") { enqueue_log_context_job } }

          seen.should eq("req-456")
          logs.check(:notice, /^Received/).entry.context[:request_id]?.should eq("req-456")
          logs.check(:notice, "Done").entry.context[:request_id]?.should eq("req-456")
        end
      end
    end

    it "runs a message without headers with no context" do
      with_propagated([:request_id]) do
        Log.capture("tj_lavin") do |logs|
          seen = run_log_context_job { enqueue_log_context_job }

          seen.should be_nil
          logs.check(:notice, /^Received/).entry.context[:request_id]?.should be_nil
          logs.check(:notice, "Done").entry.context[:request_id]?.should be_nil
        end
      end
    end
  end
end

private def with_propagated(keys : Array(Symbol), &)
  original = TJLavin.configuration.propagate_log_context
  begin
    TJLavin.configuration.propagate_log_context = keys
    yield
  ensure
    TJLavin.configuration.propagate_log_context = original
  end
end

private def enqueue_log_context_job : Nil
  LogContextWorkerHelper::LogContextWorker.new(name: "job").enqueue
end

private def run_log_context_job(& : -> Nil) : String?
  purge_log_context_queue
  seen = ::Channel(String?).new(1)
  LogContextWorkerHelper.callback = ->(request_id : String?) {
    seen.send(request_id) rescue nil
    nil
  }

  spawn name: "tjlavin-log-context-runner" do
    TJLavin::Runner.start(["spec_log_context"])
  end
  sleep 1.second

  yield

  select
  when value = seen.receive
    # Let the runner log "Done" after the job returns.
    sleep 200.milliseconds
    value
  when timeout(10.seconds)
    raise "Timeout waiting for the log context job"
  end
ensure
  LogContextWorkerHelper.callback = nil
  TJLavin::Runner.stop
  sleep 1.5.seconds
end

private def purge_log_context_queue : Nil
  AMQP::Client.start(TJLavin.connection_url) do |c|
    c.channel do |ch|
      ch.queue("spec_log_context", args: AMQP::Client::Arguments.new({"x-max-priority": 255})).purge
    end
  end
end

private def fetch_log_context_headers : Hash(String, String)
  AMQP::Client.start(TJLavin.connection_url) do |c|
    c.channel do |ch|
      q = ch.queue("spec_log_context", args: AMQP::Client::Arguments.new({"x-max-priority": 255}))
      msg = q.get(no_ack: true) || raise "No message on spec_log_context"
      headers = Hash(String, String).new
      msg.properties.headers.try &.each do |name, value|
        headers[name] = value.to_s if name.starts_with?(TJLavin::LogContext::HEADER_PREFIX)
      end
      headers
    end
  end
end
