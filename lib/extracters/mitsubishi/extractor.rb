require_relative "../../../lib/extracters/base/base_extractor"
require_relative "../../../lib/utils/http_get"
require "pry"
require "awesome_print"
require 'logging'
require 'logger'
require_relative "op_format.rb"

class Extractor < BaseExtractor
  def initialize(make, zipcode)
    super(make, zipcode)
    @http_get = HttpGet.new(%w[shader shader shader squid squid shader], nil, {shuffle_prefs: true}, @logger)
  end
  
  def load_target_page()
    @target_url = @config["target_page"].gsub(/##ZIPCODE##/, "#{@zipcode}")
    @response = @http_get.get(@target_url, {json_res: true, curl_opts: [get_standard_headers]})
  end
  
  def set_zip_code()
    
  end
  
  def extract_lease_data()
    
    lease_output_data = []
    if(@response.nil? || @response.empty?)
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "MITSUBISHI"
      @logger.info "No lease data found for #{@zipcode}" 
      lease_output_data << output 
      return OpFormat.convert_to_json(lease_output_data,"lease_data")
    end
    @response["offerSorted"].each{|attributes|
        next if !attributes["type"].include? "LEASE"
        output = OpFormat.new                   #creating instance of OpFormat
        output.zip = @zipcode             #Populating instance with scraped data
        output.brand = "MITSUBISHI"
        output.emi = attributes["leaseAmount"]
        output.emi_months = attributes["leaseMonth"]
        output.model_details =  "Model Code - #{attributes["modelCode"]}"
        output.down_payment =  attributes["leaseDownPayment"]
        output.offer_start_date = attributes["startDate"]
        output.offer_end_date = attributes["endDate"]
        output.security_deposit = nil
        output.acquisition_fee = attributes["leaseNetCapitalizedCostAquisitionFee"]
        output.offer_type = "Lease"                 #attributes["displayType"]
        output.msrp = attributes["msrp"]
        output.title1 = attributes["vehicleName"]
        output.title2 = attributes["displayType"]
        output.offer1 =  attributes["indexDescriptions"]["headlineText"]
        output.offer2 =  attributes["indexDescriptions"]["long"]
        output.due_at_signing = output.offer2.match(/\/ (\$.*?) due at lease signing/)[1] rescue nil
        output.disclaimer1 = attributes["indexDescriptions"]["legal"]
        (output.offer2.include? "Excludes tax")? (output.tax_registration_exclusion = "Y") : (output.tax_registration_exclusion = "N") rescue nil
        output.mileage_charge = output.disclaimer1.scan(/\$\d+.\d+\sper mile over.*miles\/year/)[0] rescue nil
         
        lease_output_data << output  #Saving instance in an array
      }
      @logger.info "Total #{lease_output_data.size} records found for #{@zipcode}"
   OpFormat.convert_to_json(lease_output_data, "lease_data") #Converting array of output objects in to json format
  end
  
  def extract_finance_data()
    finance_output_data = []
    if(@response.nil? || @response.empty?)
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "MITSUBISHI"
      @logger.info "No finance data found for #{@zipcode}" 
      finance_output_data << output 
      return OpFormat.convert_to_json(finance_output_data,"finance_data")
    end
    @response["offerSorted"].each{|attributes|
      begin
      next if attributes["displayType"].include? "LEASE"
      output = OpFormat.new                   #creating instance of OpFormat
      output.zip = @zipcode             #Populating instance with scraped data
      output.brand = "MITSUBISHI"
      output.model_details =  "Model Code - #{attributes["modelCode"]}"
      output.apr_rate = attributes["apr"] if attributes["displayType"].include? "APR"
      output.emi_months = attributes["aprMonth"] if attributes["displayType"].include? "APR" 
      output.cashback_amount = attributes["amount"] #if attributes["displayType"].include? "CASH"
#      output.offer_type = attributes["displayType"]
      attributes["displayType"] == "APR" ?  output.offer_type = "Finance" : output.offer_type = "Other"
      output.offer_start_date = attributes["startDate"]
      output.offer_end_date = attributes["endDate"]
      output.title1 = attributes["vehicleName"]
      output.title2 = attributes["displayType"]
      output.offer1 =  attributes["indexDescriptions"]["headlineText"]
      output.offer2 =  attributes["indexDescriptions"]["long"]
      output.disclaimer1 = attributes["indexDescriptions"]["legal"]
      rescue Exception => e
        @logger.debug "Error to grab listings- #{e.message} - #{e.backtrace.join("\n")}"
        @logger.error "Error in  Fetching data for zipcode = #{@zipcode}"
      end
      finance_output_data << output
    }
    @response["globalOffers"].each{|attributes|
      begin
      output = OpFormat.new                   #creating instance of OpFormat
      output.zip = @zipcode             #Populating instance with scraped data
      output.brand = "MITSUBISHI"
#      output.model_details =  "Model Code - #{attributes["details"][0]["modelCode"]}"
      output.cashback_amount = attributes["details"][0]["amount"] #if attributes["displayType"].include? "CASH"
      output.offer_type = "Other"
      output.offer_start_date = attributes["details"][0]["startDate"]
      output.offer_end_date = attributes["details"][0]["endDate"]
      output.title1 = attributes["details"][0]["descriptions"][0]["text"]
      output.title2 = attributes["details"][0]["displayType"]
      output.offer1 =  attributes["details"][0]["descriptions"][0]["text"]
      output.offer2 =  attributes["details"][0]["descriptions"][1]["text"]
      output.disclaimer1 = attributes["details"][0]["descriptions"][2]["text"].split("<br/>")[0]
      output.disclaimer2 = attributes["details"][0]["descriptions"][2]["text"].split("<br/>")[1]
      rescue Exception => e
        @logger.debug "Error to grab listings- #{e.message} - #{e.backtrace.join("\n")}"
        @logger.error "Error in  Fetching data for zipcode = #{@zipcode}"
      end
      finance_output_data << output
    }
    @logger.info "Total #{finance_output_data.size} records found for #{@zipcode}"
   OpFormat.convert_to_json(finance_output_data, "finance_data") #Converting array of output objects in to json format
  end
 
  def get_standard_headers
    @config["headers"].join(" ")
  end
  
end