require_relative "../../../lib/extracters/base/base_extractor"
require_relative "../../../lib/utils/http_get"
require "pry"
require "awesome_print"
require 'logging'
require 'logger'
require 'nokogiri'
require_relative "op_format.rb"

class Extractor < BaseExtractor
  
  def initialize(make, zip)
    super(make, zip)
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
      output.brand = "SUBARU"
      @logger.info "No lease data found for #{@zipcode}" 
      lease_output_data << output 
      return OpFormat.convert_to_json(lease_output_data,"lease_data")
    end
    @response.each_with_index{|dealer, index|
      next if index !=0   # taking only the first dealer
      dealer_id = dealer["dealer"]["id"]
      dealer_url = "https://www.subaru.com/services/specialoffers/models?dealerCode=" + "#{dealer_id}"
      @dealer_response = @http_get.get(dealer_url, {json_res: true, curl_opts: [get_standard_headers]})
      @dealer_response["incentives"].each{|types|
        types[1].each{ |year|
          year[1].each{|details|
            next if  details["type"] != "Lease"
          output = OpFormat.new                   #creating instance of OpFormat
          output.zip = @zipcode
          output.brand = "SUBARU"
          output.emi = details["payment"].to_s
          output.emi_months = details["term"].to_s
          output.down_payment =  details["downPayment"].to_s
          output.offer_start_date = details["startDate"]["fullDate"].split("T").first
          output.offer_end_date = details["endDate"]["fullDate"].split("T").first
          output.security_deposit = details["securityDeposit"].to_s
          output.msrp = details["msrp"].to_s
          output.due_at_signing = details["dueAtSigning"].to_s
          output.title1 = "Lease Offer"
          output.title2 = details["title"].match(/(201.*) for/)[1] rescue nil
          output.offer1 =  details["title"]
          output.offer2 =  details["details"].match(/(Now.*?2018)/)[1] rescue nil
          output.offer3 =  details["details"] 
          output.disclaimer1 = details["disclaimer"] 
          output.mileage_charge = output.disclaimer1.scan(/\d+\scents\/mile.*miles\/year/)[0] rescue nil
          output.disposition_fee = output.disclaimer1.scan(/(\$\d+)\sdisposition fee/).flatten[0] rescue nil
         (output.disclaimer1.include? "excludes tax")? (output.tax_registration_exclusion = "Y") : (output.tax_registration_exclusion = "N") rescue nil
          output.offer_type = "Lease"
          output.dealer_zip = @dealer_response["zipcode"]
          output.dealer_url = @response[0]["dealer"]["siteUrl"]
          output.dealer_name = @response[0]["dealer"]["name"]
          lease_output_data << output
          }
          
        }
      
      }
    }
    @logger.info "Total #{lease_output_data.size} records found for #{@zipcode}"
   OpFormat.convert_to_json(lease_output_data, "lease_data") #Converting array of output objects in to json format
  end
  
  def extract_finance_data()
    finance_output_data = []
    if(@response.nil? || @response.empty?)
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "SUBARU"
      @logger.info "No finance data found for #{@zipcode}" 
      finance_output_data << output 
      return OpFormat.convert_to_json(finance_output_data,"finance_data")
    end
    
    
      @dealer_response["incentives"].each{|types|
      types[1].each{ |year|
          year[1].each{|details|
          next if  details["type"] == "Lease"
          output = OpFormat.new                   #creating instance of OpFormat
          output.zip = @zipcode
          output.brand = "SUBARU"
          output.emi_months = details["details"].scan(/Financing for \d+ months/)[0].gsub(/Financing for | months/,'') rescue nil
          output.offer_start_date = details["startDate"]["fullDate"].split("T").first
          output.offer_end_date = details["endDate"]["fullDate"].split("T").first
          details["type"] == "LowRate"? output.offer_type="Finance" : output.offer_type="Other"
          output.title1 = output.offer_type + " Offer"
          output.title2 = details["title"].scan(/201.*/)[0].gsub(" Models",'') rescue nil
          output.offer1 =  details["title"]
          output.offer2 =  details["details"].match(/(Now.*?2018)/)[1] rescue nil
          output.offer3 =  details["details"] 
          output.disclaimer1 = details["disclaimer"] 
          output.apr_rate = output.offer1.scan(/\d+%\sAPR|\d+.\d+%\sAPR/)[0].sub(" APR","") rescue nil
          output.dealer_zip = @dealer_response["zipcode"]
          output.dealer_url = @response[0]["dealer"]["siteUrl"]
          output.dealer_name = @response[0]["dealer"]["name"]
          finance_output_data << output
          }
          
        }
      
      }
    other_offers_url = "https://www.subaru.com/special-offers/index.html"
    other_offers_response = @http_get.get(other_offers_url, {json_res: false, curl_opts: [other_offer_headers]})
    other_response = Nokogiri::HTML(other_offers_response)
    other_offers = other_response.xpath("//div[@class='specialprograms parsys']/div[@class='specialprograms parbase section']")
    
    other_offers.each{|offer|
      output = OpFormat.new                   #creating instance of OpFormat
      output.zip = @zipcode
      output.brand = "SUBARU"
      output.offer_type = "Other"   
      output.title1 = offer.xpath(".//div[@class='offer_details']/p[@class='full_title']").text
      output.disclaimer1 = offer.xpath(".//div[@class='offer_details']/p[@class='full_title']/following-sibling::p").text
      finance_output_data << output
    }
    @logger.info "Total #{finance_output_data.size} records found for #{@zipcode}"
   OpFormat.convert_to_json(finance_output_data, "finance_data") #Converting array of output objects in to json format
    
  end
  
  def get_standard_headers
    @config["headers"].join(" ")
  end
  
  def other_offer_headers
    @config["other_offers"].join(" ")
  end
  
end