require 'json'
require 'ap'
require_relative "../../../lib/extracters/base/base_extractor"
require_relative "../../../lib/utils/http_get.rb"
require_relative "op_format.rb"

class Extractor < BaseExtractor
  def initialize(make, zipcode)
    super(make, zipcode)
    @http_get = HttpGet.new(%w[shader shader shader squid squid shader], nil, {shuffle_prefs: true}, @logger)
  end
  
  def load_target_page()
#    target_url = @config["target_page"]
#    response = @http_get.get(target_url, {json_res: false, curl_opts: [get_standard_headers]})
    @offer_page_url = @config["offer_page_url"].gsub("###zipcode###",@zipcode)
    @response = JSON.parse(@http_get.get(@offer_page_url, {json_res: true, curl_opts: [get_offer_page_headers]}).to_json)
  end
  
  def set_zip_code()
    
  end
  
  def extract_lease_data()
    lease_output_data = []
    if !@response.nil? && !@response["offers"]["models"].empty?
      @response["offers"]["models"].each do |model|
        model["offerTypes"].each do |_offer|
        next if _offer["name"] != "Lease"
        _offer["offers"].each do |offer|
          output = OpFormat.new
          output.brand = "MINI"
          output.zip = @zipcode 
          output.model_details = offer["legalCode"]
          output.title1 = model["name"] rescue nil
          output.title2 = _offer["name"] if _offer["name"] == "Lease"
          output.title3 = offer["title"].split(".")[0].gsub("Lease a ","") rescue nil
          output.offer1 = offer["title"].split(".")[1].strip rescue nil
          output.offer2 = offer["title"].split(".")[2].strip rescue nil
          output.emi = offer["offerValues"][0]["offerValue"] rescue nil
          output.emi_months = offer["title"].split(".")[1].strip.scan(/\d+/)[1]
          output.down_payment =  offer["title"].split(".")[2].gsub(",","").match(/\d+/).to_s
          output.offer_start_date = nil
          output.offer_end_date =  nil
          output.disclaimer1 = OpFormat.parse_text(offer["legal"])
          output.offer_type = offer["offerValues"][0]["offerValueTypeCode"]=="LEASE"? "Lease":"Finance"
          output.acquisition_fee = output.disclaimer1.match("\\$\\d+ acquisition fee").to_s.gsub(" acquisition fee","") rescue nil
          output.due_at_signing = output.disclaimer1.match("\\$(\\d+\,\\d+) Cash due at signing").to_s.gsub(" Cash due at signing","") rescue nil
          output.mileage_charge = output.disclaimer1.match("\\W\.\\d+\/mile").to_s rescue nil
          output.disposition_fee = output.disclaimer1.match("\\$\\d+ at lease end").to_s.gsub(" at lease end","") rescue nil
          output.tax_registration_exclusion = (output.disclaimer1.include?"Tax, title, license, registration and dealer fees are additional fees due at signing")? "Y":"N" rescue nil
          output.disclaimer2 = nil
          lease_output_data << output
        end
        end
      end
    end
    if lease_output_data.empty?
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "MINI"
      lease_output_data << output
    end
   return OpFormat.convert_to_json(lease_output_data,"lease_data")   #Converting array of output objects in to json format
  end
  
  def extract_finance_data()
    lease_output_data = []
    if !@response.nil? && !@response["offers"]["models"].empty?
      @response["offers"]["models"].each do |model|
        model["offerTypes"].each do |_offer|
        next if _offer["name"] != "Finance"
        _offer["offers"].each do |offer|
          output = OpFormat.new
          output.brand = "MINI"
          output.zip = @zipcode 
          output.model_details = offer["legalCode"]
          output.title1 = model["name"] rescue nil
          output.title2 = _offer["name"] if _offer["name"] == "Finance"
          title = offer["title"].split(",")[0].split(" on")[1].strip.gsub(" models","")
          output.title3 = (title.include?"remaining ")? title.gsub("remaining ",""):title
          output.offer1 = offer["title"] rescue nil
          output.apr_rate = "#{offer["offerValues"][0]["offerValue"]}%" rescue nil
          output.emi_months = offer["title"].split(",")[0].split(" on")[0].scan(/\d+/)[2]
          output.offer_type = offer["offerValues"][0]["offerValueTypeCode"]=="LEASE"? "Lease":"Finance"
          #output.down_payment =  offer["title"].split(".")[2].gsub(",","").match(/\d+/).to_s
          output.offer_start_date = nil
          output.offer_end_date =  nil
          output.disclaimer1 = OpFormat.parse_text(offer["legal"])
          output.tax_registration_exclusion = (output.disclaimer1.include?"Taxes, title and registration fees extra")? "Y":"N" rescue nil
          output.disclaimer2 = nil
          lease_output_data << output
        end
        end
      end
    end
    if lease_output_data.empty?
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "MINI"
      lease_output_data << output
    end
    return OpFormat.convert_to_json(lease_output_data,"finance_data")  #Converting array of output objects in to json format
  end
  
#  def get_standard_headers
#    @config["Headers"].join(" ")
#  end 
  
  def get_offer_page_headers
    @config["Offer_page_headers"].join(" ").gsub("###zipcode###",@zipcode)
  end 
end




