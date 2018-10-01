require 'json'
require 'ap'
require_relative "../../../lib/extracters/base/base_extractor"
require_relative "../../../lib/utils/http_get.rb"
require_relative "./op_format"

class Extractor < BaseExtractor
  def initialize(make, zipcode)
    super(make, zipcode)
    @http_get = HttpGet.new(%w[shader shader shader squid squid squid], nil, {shuffle_prefs: true}, @logger)
  end
  
  def load_target_page()
    target_url = @config["target_page"].gsub("###ZIP###", @zipcode.to_s)
    @response = JSON.parse(@http_get.get(target_url, {json_res: true, curl_opts: [get_standard_headers]}).to_json) 
  end
  
  def set_zip_code()
    
  end
  
  def scraping_lease_offers(_lease_offer)
    lease_offers_arr = []
    title1 = "#{_lease_offer["modelYear"]} #{_lease_offer["modelName"]}"
    title5 = "LEASE OFFER"
    _lease_offer["leaseOffers"].each{ |offer|
      begin
        emi = !offer["monthlyPayment"].empty? ? "$#{offer["monthlyPayment"]}" : nil
        downpayment = !offer["leaseDownPayment"]rescue nil
        leasecashback = offer["leaseCashBack"] == "" ?  nil :  offer["leaseCashBack"]
        security_deposit = !offer["leaseSecurityDeposit"].empty? ? "$#{offer["leaseSecurityDeposit"]}" : nil
        
        title2 = offer["leaseHeader"]
        offer2 = offer["leaseDetail"]
        offer1 = offer2.split(',').first
        title3, title4 = offer["specs"].map{ |_specs| _specs["value"].gsub("&nbsp;", ' ') } if !offer["specs"].nil? && offer["specs"].is_a?(Array)
        disclaimer = OpFormat.parse_text(offer["disclaimer"]).gsub(/<("[^"]*"|'[^']*'|[^'">])*>/, '')
      rescue 
      end
      output = OpFormat.new                   #creating instance of OpFormat
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "MAZDA"
      output.model_details = offer["modelCode"] rescue nil
      output.emi = emi
      output.down_payment = downpayment
      output.security_deposit = security_deposit
      output.title1 = title1
      output.title2 = title2
      output.title3 = title3
      output.title4 = title4
      output.title5 = title5
      output.offer1 = offer1
      output.offer2 = offer2
      output.disclaimer1 = disclaimer
      output.tax_registration_exclusion = offer["leaseDetail"].scan(/Excludes.*\./).first.nil? ? "N" : "Y" rescue nil
      output.acquisition_fee = offer["description"].gsub(/(.*)(\$.* acquisition fee)(.*)/,'\2').gsub("acquisition fee",'') rescue nil
      output.offer_type = "Lease"
      output.msrp =  offer["dealerDisclaimer"].scan(/MSRP \$.* plus \$/).first.gsub(/ plus \$|MSRP/,'') rescue nil
      output.mileage_charge =  offer["disclaimer"].scan(/.Lessee.*\mile./).first.strip rescue nil
      output.due_at_signing = "$#{offer["dueAtSigning"]}" rescue nil
      output.emi_months = offer["leaseTerm"].to_s rescue nil
      output.cashback_amount = leasecashback rescue nil
      
      lease_offers_arr << output
    }

    lease_offers_arr.flatten
  end
  
  
  def extract_lease_data()
    lease_output_data = []
    if @response.nil?
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "MAZDA"
      @logger.info "No lease data found for #{@zipcode}" 
      lease_output_data << output 
      return OpFormat.convert_to_json(lease_output_data , "lease_data")
    end
    
    @response["body"]["regionalIncentives"]["leaseOffers"].each{ |_lease_offer|
      lease_output_data << scraping_lease_offers(_lease_offer)       
    }

    OpFormat.convert_to_json(lease_output_data.flatten , "lease_data")   #Converting array of output objects in to json format
  end
  def extract_finance_data
    finance_output_data = []
    if @response["body"]["regionalIncentives"]["purchaseOffers"].nil?
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "MAZDA"
      @logger.info "No Finance data found for #{@zipcode}" 
      finance_output_data << output 
      return OpFormat.convert_to_json(finance_output_data , "finance_data")
    else
      @response["body"]["regionalIncentives"]["purchaseOffers"].each{|offers|
        offers["purchaseOffers"].each{|offer|
          finance =   offer["description"].include?("APR")
          cash = offer["description"].include?("CASH")
          if finance
            output = OpFormat.new 
            output.brand = "MAZDA"
            output.model_details = offers["modelCode"]
            output.zip = @zipcode
            output.title1 = "#{offers["modelYear"]} #{offers["modelName"]}" rescue nil
            output.title2 = 'Purchase Offers'
            purchase_offers =  offers["purchaseOffers"]           rescue nil
            output.apr_rate = offer["apr"]           rescue nil
            output.title3 = "#{offer["apr"]} %APR"   rescue nil
            output.offer1 = offer["description"]     rescue nil
            output.disclaimer1 = OpFormat.parse_text(offer["disclaimer"]).gsub(/<("[^"]*"|'[^']*'|[^'">])*>/, '') rescue nil
            output.emi_months = offer["paymentTerm"]
            output.offer_type = "Finance"
            finance_output_data << output                         rescue nil
          elsif cash
            output = OpFormat.new 
            output.brand = "MAZDA"
            output.model_details = offers["modelCode"] rescue nil
            output.zip = @zipcode
            output.offer_type = "Other"
            output.title1 = "#{offers["modelYear"]} #{offers["modelName"]}" rescue nil
            output.title2 = 'Purchase Offers'
            output.title3 = "Customer Cash"
            output.cashback_amount = "$#{offer["cashBack1"]}" rescue nil
            output.offer1 = offer["description"] rescue nil
            output.title4 = "#{offers["purchaseOffers"][0]["apr"]} %APR"   rescue nil
            output.disclaimer1 = OpFormat.parse_text(offer["disclaimer"]).gsub(/<("[^"]*"|'[^']*'|[^'">])*>/, '') rescue nil
            output.apr_rate = offers["purchaseOffers"][0]["apr"] rescue nil
            finance_output_data << output                         
          end
        }
      }
    end
    finance_output_data.flatten! if !finance_output_data.empty?
    OpFormat.convert_to_json(finance_output_data.flatten , "finance_data")  
  end
  def get_standard_headers
    @config["headers"].join(" ")
  end 
end



