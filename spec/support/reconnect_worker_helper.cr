module ReconnectWorkerHelper
  # Tests need a way to observe that a job actually ran, since the runner
  # acks asynchronously. The spec sets `callback` before enqueueing.
  class_property callback : Proc(String, Nil)? = nil

  class ReconnectWorker < TJLavin::QueuedJob
    queue "spec_reconnect"

    param name : String

    def perform
      if cb = ReconnectWorkerHelper.callback
        cb.call(name)
      end
    end
  end
end
