module CustomQueueWorkerHelper
  class MediaWorker < TJLavin::QueuedJob
    queue "media_processing"

    param media_id : String

    def perform
      "Processing media: #{media_id}"
    end
  end

  class DefaultQueueWorker < TJLavin::QueuedJob
    param task : String

    def perform
      "Running task: #{task}"
    end
  end
end
