require 'csv'
require 'pry-byebug'
require 'faraday'
require 'benchmark'


# csv writter takes an ordered list of rows then writtes them into the target file
class CSVWritter
  def initialize(rows)
    @rows = rows
    @file = CSV.open("temp_and_cases_parallel.csv", "ab")
  end
  def writte
    @rows.each do |row|
      if row.index == 1
        @file << row.headers
      end
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
    raise RateLimitExceededError
    raise RateLimitExceededError if response.body.start_with?("You have exceeded the maximum number of daily requests")
    CSV.parse(response.body, headers: true)&.first || OpenStruct.new(fields: Array.new(25, "NA"), headers: [])
  end
end

class ThreadPool
  def initialize(size: 25)
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

  threads = []
  rows = []
  Thread.abort_on_exception = false
  thread_pool = ThreadPool.new
  thread_pool.start
    CSV.foreach("cases_by_region.csv", headers: true).with_index(1) do |case_by_region_row, index|
      begin
        thread_pool.schedule do
          climate_data = VisualCrossingWebServices.new(case_by_region_row, index, conn).fetch_historical_data
          rows.push(Row.new(
                  data: climate_data.fields + case_by_region_row.fields,
                  headers: climate_data.headers + case_by_region_row.headers,
                  index: index
                ))
        end
      rescue VisualCrossingWebServices::RateLimitExceededError => e
        puts('Im propagated to main thread')
        break
      end
    end
    sleep(1) until thread_pool.inactive?
    # problem here is that I need to process the all cases_by_region csv before writting to the result file
    binding.pry
    sorted_rows = rows.sort_by {|row| row.index}
    CSVWritter.new(sorted_rows).writte
  # end
}
