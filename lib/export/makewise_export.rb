require 'csv'
require 'json'
require_relative './export_fields'
require "ap"
require "pry"
require 'logger'
def export(response, make, zipcode,  export_dir)
  if !response["listings"].nil? && !response["listings"]["lease_data"].empty?
    get_export_fields =[]
    get_export_fields = CSV.read("#{export_dir}/lease_headers.csv")[0]
    
    listing_count = response["listings"]["lease_data"].size rescue 0
    @logger.debug "#{listing_count} records for  MAKE = #{make} | ZIP = #{zipcode}"
    CSV.open("#{export_dir}/lease_export.csv", "a") { |csv| 
      list_arr = []
      response["listings"]["lease_data"].each{|listing|
        get_export_fields.each{|field|
          list_arr << listing[field] 
        }
        csv << list_arr.flatten
      }
    }
  else
    @logger.error "RESPONSE IS NIL FOR MAKE = #{make} | ZIP = #{zipcode}"
  end
end

def main
  make, zipcode, export_dir = ARGV[0], ARGV[1], ARGV[2]
  date = (Date.today).strftime('%Y-%m-%d')
  log_dir = "#{ENV["HOME"]}/lease_export/logs/#{date}"
  @logger = Logger.new("#{log_dir}/#{make}_lease_export.log", 10, 10240000)
  ip_address = `hostname -I`.chomp.split(" ")[0] rescue nil
  res = `curl 'http://#{ip_address}:4567/lease?make=#{make}&zipcode=#{zipcode}'`
  
  if res != "" || !res.nil?
    begin
      response = JSON.parse(res)
      export(response,  make,zipcode,  export_dir ) 
      @logger.debug("Export success for Make = #{make} | Zipcode = #{zipcode}")
    rescue  Exception => e
      @logger.error e.backtrace
    end
  else
    @logger.error("Failed to generate export for Make = #{make} | Zipcode = #{zipcode}")
  end
end
  
if __FILE__ == $0
  main 
end 