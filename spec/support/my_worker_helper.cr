module MyWorkerHelper
  class MyWorker < TJLavin::QueuedJob
    param name : String

    def perform
      "Performing MyWorker with name: #{name}"
    end
  end
end
