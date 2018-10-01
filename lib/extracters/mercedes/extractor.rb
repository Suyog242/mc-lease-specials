require 'json'
require 'ap'
require 'nokogiri'
require_relative "../../../lib/extracters/base/base_extractor"
require_relative "../../../lib/utils/http_get.rb"
require_relative "op_format.rb"

class Extractor < BaseExtractor
  def initialize(make, zipcode)
    super(make, zipcode)
    @http_get = HttpGet.new(%w[shader shader shader shader], nil, {shuffle_prefs: true}, @logger)
  end
  
  def load_target_page()
    @target_url = @config["target_page"].gsub("###zipcode###",@zipcode.to_s)
    @response = @http_get.get(@target_url, {json_res: true, curl_opts: [get_standard_headers]})
  end
  
  def set_zip_code()
    return nil
  end
  
  def extract_lease_data()
    lease_output_data = []
    
    @response["_embedded"]["national_offer"].each do |offer|
      next if offer["offer_type"]!= "Lease"
      output = OpFormat.new                   #creating instance of OpFormat
      output.zip = @zipcode                  #Populating instance with scraped data
      output.offer_type = "Lease"
      output.brand = "MERCEDES"
      output.msrp = offer["msrp"]
      output.acquisition_fee = offer["acquisition_fee"]
      output.emi = offer["monthly_payment"] rescue nil
      output.emi_months = offer["term_min"] rescue nil
      output.down_payment = offer["total_due"] rescue nil
      output.offer_start_date = offer["start_date"]["date"].split(" ")[0] rescue nil
      output.offer_end_date = offer["expiration_date"]["date"].split(" ")[0] rescue nil
      output.security_deposit = nil
      output.title1 = offer["vehicle_make"] rescue nil
      output.title2 = offer["offer_type"] rescue nil
      output.title3 = offer["vehicle_model"] rescue nil
      output.offer1 = "Lease #{offer["monthly_payment"]}/month" rescue nil
      output.offer2 = "#{offer["total_due"]} due at signing" rescue nil
      disclaimer = Nokogiri::HTML(offer["full_description"])
      output.disclaimer1 = OpFormat.parse_text(disclaimer.xpath(".//p/text()").text()) rescue nil
      output.disclaimer2 = nil
      lease_output_data << output             #Saving instance in an array
    end
    
    if(lease_output_data.empty?)
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "MERCEDES"
      output.offer_type = "Lease"
      @logger.info "No lease data found for #{@zipcode}" 
      lease_output_data << output 
    end
    
    OpFormat.convert_to_json(lease_output_data,"lease_data")   #Converting array of output objects in to json format
  end
  
  def extract_finance_data()
    lease_output_data = []
    
    @response["_embedded"]["national_offer"].each do |offer|
      next if offer["offer_type"]!= "Finance"
      output = OpFormat.new                   #creating instance of OpFormat
      output.zip = @zipcode                  #Populating instance with scraped data
      output.offer_type = "Finance"
      output.apr_rate = "#{offer["apr"]}%" rescue nil
      output.brand = "MERCEDES"
      output.msrp = offer["msrp"]
      output.model_details = offer["vehicle_model"] rescue nil
      output.acquisition_fee = offer["acquisition_fee"]
      output.emi_months = offer["term_min"] rescue nil
      output.down_payment = offer["total_due"] rescue nil
      output.offer_start_date = offer["start_date"]["date"].split(" ")[0] rescue nil
      output.offer_end_date = offer["expiration_date"]["date"].split(" ")[0] rescue nil
      output.security_deposit = nil
      output.title1 = offer["vehicle_make"] rescue nil
      output.title2 = offer["offer_type"] rescue nil
      output.title3 = offer["vehicle_model"] rescue nil
      output.offer1 = "#{offer["apr"]}%" rescue nil
      output.offer2 = offer["short_description"].gsub("<sup>1</sup>","") rescue nil
      disclaimer = Nokogiri::HTML(offer["full_description"])
      apr_offers = disclaimer.xpath("//div[@class='finance-description']//p").text
      apr_offer = apr_offers.split(" or ")[1] rescue nil
      lease_output_data << output = apr_offer(apr_offer,offer) if !apr_offer.nil? 
      output.disclaimer1 = OpFormat.parse_text(disclaimer.xpath(".//p/text()").text()) rescue nil
      output.disclaimer2 = nil
      lease_output_data << output             #Saving instance in an array
    end
    
    if(lease_output_data.empty?)
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "MERCEDES"
      output.offer_type = "Finance"
      @logger.info "No finance data found for #{@zipcode}" 
      lease_output_data << output 
    end
    
    OpFormat.convert_to_json(lease_output_data,"finance_data")   #Converting array of output objects in to json format
  end
  
  def apr_offer(apr_offer,offer)
    output = OpFormat.new
    output.zip = @zipcode                  #Populating instance with scraped data
      output.offer_type = "Finance"
      output.apr_rate = apr_offer.match("\\d+\\.\\d+").to_s rescue nil
      output.brand = "MERCEDES"
      output.msrp = offer["msrp"]
      output.model_details = offer["vehicle_model"] rescue nil
      output.acquisition_fee = offer["acquisition_fee"]
      output.emi_months = apr_offer.match("percent APR for \\d+").to_s.gsub("percent APR for ","") rescue nil
      output.down_payment = offer["total_due"] rescue nil
      output.offer_start_date = offer["start_date"]["date"].split(" ")[0] rescue nil
      output.offer_end_date = offer["expiration_date"]["date"].split(" ")[0] rescue nil
      output.security_deposit = nil
      output.title1 = offer["vehicle_make"] rescue nil
      output.title2 = offer["offer_type"] rescue nil
      output.title3 = offer["vehicle_model"] rescue nil
      output.offer1 = "#{offer["apr"]}%" rescue nil
      output.offer2 = offer["short_description"].gsub("<sup>1</sup>","") rescue nil
      disclaimer = Nokogiri::HTML(offer["full_description"])
      output.disclaimer1 = OpFormat.parse_text(disclaimer.xpath(".//p/text()").text()) rescue nil
    return output
  end
  
  def get_standard_headers
    @config["headers"].join(" ")
  end 
end