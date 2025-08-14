module MyWorkerHelper
  class MyWorker < TJLavin::QueuedJob
    param name : String

    def perform
      puts "Performing MyWorker with name: #{name}"
    end
  end
end
