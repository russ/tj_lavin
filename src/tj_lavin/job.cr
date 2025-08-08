require "./serializers/*"

module TJLavin
  Log = ::Log.for(self)

  abstract class Job
    Log = ::Log.for(self)

    include Serializers::Primitives

    getter exception : Exception?

    def run
      perform
    rescue e
      Log.warn(exception: e) do
        "Job failed! Raised #{e.class}: #{e.message}"
      end

      @exception = e
    end

    def perform
      Log.error { "No job definition found for #{self.class.name}" }
      fail
    end

    def fail(reason = "")
      raise JobFailed.new(reason)
    end
  end
end
