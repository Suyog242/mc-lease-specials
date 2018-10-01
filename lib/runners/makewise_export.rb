require 'csv'
require 'json'
#require_relative './export_fields'
require "ap"
require "pry"
require 'logger'
def export(response, make, zipcode, export_dir, data_type)
  if !response.nil? && !response["#{data_type}"].empty?
    get_export_fields =[]
    get_export_fields = CSV.read("#{export_dir}/chrome_headers.csv")[0]
    listing_count = response["#{data_type}"].size rescue 0
    @logger.debug "#{listing_count} records for  MAKE = #{make} | ZIP = #{zipcode}"
    CSV.open("#{export_dir}/chrome_export.csv", "a") { |csv| 
      csv.flock(File::LOCK_EX)
      response["#{data_type}"].each{|listing|
        list_arr = []
        get_export_fields.each{|field|
          list_arr << listing[field] 
        }
        csv << list_arr.flatten if !list_arr.empty?
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
  begin
    require_relative "../../lib/extracters/#{make}/extractor"
    extr = Extractor.new(make, zipcode)
    extr.load_target_page()
    extr.set_zip_code()
    lease_res = extr.extract_lease_data()
    finance_res = extr.extract_finance_data()
    
    if lease_res != "" || !lease_res.nil?
      #response = JSON.parse(res)
      export(lease_res, make, zipcode, export_dir, "lease_data") 
      @logger.debug("Export success for Make = #{make} | Zipcode = #{zipcode}")
    else
      @logger.error("Failed to generate lease export for Make = #{make} | Zipcode = #{zipcode}")
    end
    
    if finance_res != "" || !finance_res.nil?
      #response = JSON.parse(res)
      export(finance_res, make, zipcode, export_dir, "finance_data") 
      @logger.debug("Export success for Make = #{make} | Zipcode = #{zipcode}")
    else
      @logger.error("Failed to generate finance export for Make = #{make} | Zipcode = #{zipcode}")
    end
    
  rescue  Exception => e
    @logger.error e.backtrace
  end
end
  
if __FILE__ == $0
  main 
end 
