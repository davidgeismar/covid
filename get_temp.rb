require 'csv'
require 'pry-byebug'
require 'faraday'
require 'ostruct'

api_key = "2YXV4EUUFVIXJ5Z8976N180CP"
retry_options = {
  max: 10,
  interval: 3,
  interval_randomness: 0.5,
  backoff_factor: 2
}

conn = Faraday.new do |f|
  f.request :retry, retry_options
end

CSV.open("temp_and_cases.csv", "ab") do |temp_and_cases|
  CSV.foreach("cases_by_region.csv", headers: true).with_index(1) do |row, index|
    next if index < 26442
    uri = "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/weatherdata/history?&aggregateHours=24&startDateTime=#{row["day"].strip}T00:00:00&endDateTime=#{row["day"].strip}T23:59:00&unitGroup=metric&contentType=csv&location=#{row["lat"].strip},#{row["long"].strip}&key=#{api_key}"
    response = conn.get uri
    puts("calling #{uri} with index #{index}")

    climate_info = CSV.parse(response.body, headers: true)&.first || OpenStruct.new(fields: Array.new(25, "NA"))
    if index == 1
      headers = row.headers + climate_info.headers
      temp_and_cases << headers
    end
    temp_and_cases << row.fields + climate_info.fields
  end
end
