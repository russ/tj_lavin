module LogContextWorkerHelper
  class_property callback : Proc(String?, Nil)? = nil

  class LogContextWorker < TJLavin::QueuedJob
    queue "spec_log_context"

    param name : String

    def perform
      LogContextWorkerHelper.callback.try &.call(::Log.context.metadata[:request_id]?.try(&.as_s))
    end
  end
end
