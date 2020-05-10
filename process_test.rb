require 'csv'
require 'benchmark'

puts Benchmark.measure{
  a = [1, 2, 3, 4]
  target_file = CSV.open("temp_and_cases_batch_parallel.csv", "ab")
  target_file << ["hello from parent process #{Process.pid}"]
  a.each do |num|
    pid = Process.fork do
      target_file = CSV.open("temp_and_cases_batch_parallel.csv", "ab")
      target_file << ["hello from child Process #{Process.pid}"]
    end
    puts "parent, pid #{Process.pid}, waiting on child pid #{pid}"
  end

  Process.wait
  puts "parent exiting"
}
