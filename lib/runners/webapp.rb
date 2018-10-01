require 'sinatra'
require "csv"
require 'pry'
require 'getoptions'
require 'pry'
require 'logging'
require 'json'
#require './export_fields'
require 'csv'
require 'date'

get "/" do  
  {"status" => "ok"}.to_json
end

before do
  date = (Date.today).strftime('%Y-%m-%d')
  log_dir = "#{ENV["HOME"]}/lease_export/logs/#{date}"
  @logger = Logger.new("#{log_dir}/lease_api.log", 10, 10240000)


def log_app_error_response(msg)
  @logger.debug ("#{ENV["RACK_ENV"]} - #{msg}\n")
end

get "/" do
  redirect "/lease"
end

get "/lease" do 
  begin
    @logger.debug "API call for MAKE = #{params["make"]} | ZIPCODE = #{params["zipcode"]}"
    if params.has_key?("make") && !params["make"].empty? && params.has_key?("zipcode") && !params["zipcode"].empty?
      make, zipcode = params["make"], params["zipcode"]
      require_relative "../../lib/extracters/#{make}/extractor"
      extr = Extractor.new(make, zipcode)
      extr.load_target_page()
      extr.set_zip_code()
      response = extr.extract_data() rescue nil
      #export(response)
      content_type :json
      if !response.nil?
        {
          status: 200,
          message: "Lease data for Make = #{make} and Zipcode = #{zipcode}",
          listings: response
        }.to_json 
      else
        {
          status: 422,
          message: "No lease data found for Make = #{make} and Zipcode = #{zipcode}",
          listings: response
        }.to_json
      end
    end
  rescue Exception => ex
    log_app_error_response("/lease exception - #{ex.inspect}")

    {
      status: 500,
      message: "/lease exception - #{ex.inspect}",
      listings: nil
    }.to_json 
  end
end
end


