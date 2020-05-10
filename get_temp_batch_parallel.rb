require 'csv'
require 'pry-byebug'
require 'faraday'
require 'benchmark'

# csv writter takes an ordered list of rows then writtes them into the target file
class CSVWritter
  def initialize(target_file, rows)
    @rows = rows
    @file = target_file
  end
  def writte
    @rows.each do |row|
      puts "-------------------------------------"
      puts "PROCESS PID #{Process.pid} : writting #{row.data}"
      puts "-------------------------------------"
      @file << row.data
    end
  end
end

# holds data, headers and position for each row to writte
class Row
  attr_accessor :data, :headers, :index
  def initialize(args = {})
    @data = args[:data]
    @headers = args[:headers]
    @index = args[:index]
  end
end

class VisualCrossingWebServices
  class RateLimitExceededError < StandardError; end
  API_KEY = "DUMMY"
  def initialize(row, index, conn)
    @row = row
    @index = index
    @conn = conn
  end

  def fetch_historical_data
    uri = "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/weatherdata/history?&aggregateHours=24&startDateTime=#{@row["day"].strip}T00:00:00&endDateTime=#{@row["day"].strip}T23:59:00&unitGroup=metric&contentType=csv&location=#{@row["lat"].strip},#{@row["long"].strip}&key=#{API_KEY}"
    response = @conn.get uri
    puts("calling #{uri}")
    raise RateLimitExceededError if response.body.start_with?("You have exceeded the maximum number of daily requests")
    CSV.parse(response.body, headers: true)&.first || OpenStruct.new(fields: Array.new(25, "NA"), headers: [])
  end
end

class ThreadPool
  def initialize(size: 10)
    @size = size
    @tasks = Queue.new
    @pool = []
  end

  def schedule(*args, &block)
    @tasks << [block, args]
  end

  def start
    Thread.new do
      loop do
        next if @pool.size >= @size
        task, args = @tasks.pop
        thread = Thread.new do
          task.call(*args)
          end_thread(thread)
        end
        @pool << thread
      end
    end
  end

  def inactive?
    @tasks.empty? && @pool.empty?
  end

  def end_thread(thread)
    @pool.delete(thread)
    thread.kill
  end

end

class CSVSplitter
  attr_accessor :csv_headers
  def initialize(csv_path, file_count)
    temp_csv = CSV.readlines(csv_path, headers: true)
    @csv = temp_csv[0..40]
    @csv_headers = temp_csv.headers
    @row_count = temp_csv[0..40].count
    @file_count = file_count
    @chunk_size = @row_count/file_count
    @files = []
  end

  def split
    current = 0
    step = @chunk_size - 1
    file_created = 0
    while file_created < @file_count
      @files.push(@csv[current..step])
      current += (@chunk_size - 1)
      step += (@chunk_size - 1)
      file_created += 1
    end
    @files
  end
end

puts Benchmark.measure{
  RETRY_OPTIONS = {
    max: 10,
    interval: 3,
    interval_randomness: 0.5,
    backoff_factor: 2
  }
  conn = Faraday.new do |f|
    f.request :retry, RETRY_OPTIONS
  end

  splitter = CSVSplitter.new("cases_by_region.csv", 4)
  files = splitter.split

  CSV.open("temp_and_cases_batch_parallel.csv", "ab") do |target_file|
    tmp_headers = VisualCrossingWebServices.new(files.first[0], 0, conn).fetch_historical_data.headers
    puts "-------------------------------------"
    puts "ADDING HEADERS PID #{Process.pid}"
    puts "-------------------------------------"
    target_file << ['PID'] + splitter.csv_headers + tmp_headers
    target_file.flush
    files.each do |file|
      pid = Process.fork do
        threads = []
        rows = []
        thread_pool = ThreadPool.new
        thread_pool.start
        file.each_with_index do |case_by_region_row, index|
          thread_pool.schedule do
            puts "-------------------------------------"
            puts "CURRENT PROCESS PID #{Process.pid}"
            puts "-------------------------------------"
            climate_data = VisualCrossingWebServices.new(case_by_region_row, index, conn).fetch_historical_data
            rows.push(Row.new(
                    data: [Process.pid] + case_by_region_row.fields + climate_data.fields,
                    headers: climate_data.headers + case_by_region_row.headers,
                    index: index
                  ))
          end
        end
        sleep(1) until thread_pool.inactive?
        # problem here is that I need to process the all cases_by_region csv before writting to the result file
        sorted_rows = rows.sort_by {|row| row.index}

        CSVWritter.new(target_file, sorted_rows).writte
      end
      puts "parent, pid #{Process.pid}, waiting on child pid #{pid}"
    end
  end

  Process.wait
  puts "parent exiting"
}
