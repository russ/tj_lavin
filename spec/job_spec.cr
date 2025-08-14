require "./spec_helper"

describe TJLavin::Job do
  it "enqueues a job" do
    MyWorkerHelper::MyWorker.new(name: "TJ Lavin").enqueue
    # TODO: Can we check the queue or maybe update a database record?
  end
end
