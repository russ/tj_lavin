require "./spec_helper"

describe TJLavin::Job do
  it "enqueues a job" do
    name = "TJ Lavin"

    MyWorkerHelper::MyWorker.new(name: name).enqueue

    consume_jobs do |job_run|
      job_run.config.should eq({"name" => name})
      job_run.type.should eq("MyWorkerHelper::MyWorker")
      job_run.job.as(TJLavin::QueuedJob).name.should eq(name)
    end
  end
end
