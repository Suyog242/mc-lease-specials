require 'json'
require 'ap'
require_relative "../../../lib/extracters/base/base_extractor"
require_relative "../../../lib/utils/http_get.rb"
require_relative "./op_format"

class Extractor < BaseExtractor
  def initialize(make, zipcode)
    super(make, zipcode)
    @http_get = HttpGet.new(%w[shader shader shader squid squid shader], nil, {shuffle_prefs: true}, @logger)
  end
  
  def load_target_page()
    @response = JSON.parse(@http_get.get(@config["target_page"], {
          json_res: true, 
          curl_opts: [get_standard_headers, "--data '#{get_post_data}' --compressed"]
        }).to_json) 
    if !@response
      lease_output_data = []
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "GENESIS"
      @logger.info "No lease data found for #{@zipcode}" 
      lease_output_data << output 
      return OpFormat.convert_to_json(lease_output_data , "lease_data")
    end
  end
  
  def set_zip_code()
    
  end
  
  def extract_lease_data()
    lease_output_data = []
    if @response["GetBrandSpecialOffersByZipResult"].empty?
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "GENESIS"
      @logger.info "No lease data found for #{@zipcode}" 
      lease_output_data << output 
      return OpFormat.convert_to_json(lease_output_data , "lease_data")
    end
    
    vehicles_model = @response["GetBrandSpecialOffersByZipResult"].select{|hsh| hsh["Type"] == "Lease Offer" }
    vehicles_model.each{ |offer|
      details = offer["DescriptionLong"].split(/\./)
      model_info = offer["ModelName"].split('-') rescue nil
      model_name = model_info[0].upcase rescue nil
      year = model_info[1] rescue nil
      title1 = "#{year} GENESIS #{model_name}" if !year.nil? && !model_name.nil?
      offers = offer["DescriptionLong"].split(/<BR><BR>|<BR>/) rescue nil
      offer2 = offers[0].gsub(/\n+|\r+|\t+/, '').gsub(/\s{2,}/, '') rescue nil
      emi = offer2.scan(/(\$\d+).*month/).flatten[0] rescue nil
      emi_months = offer2.scan(/for\s+(\d+)\s+months/).flatten[0] rescue nil
      down_payment = offer2.scan(/(\$\d+(?:\,|)\d+) due at signing/).flatten[0] rescue nil
      offer3 = offers[2].gsub(/\n+|\r+|\t+/, '').gsub(/\s{2,}/, '') rescue nil
      offer4 = offers[3].gsub(/\n+|\r+|\t+/, '').gsub(/\s{2,}/, '') rescue nil
      disclaimer = offer["DescriptionLong"].strip rescue nil
      offer_start_date = offer["StartDate"] rescue nil
      offer_end_date = offer["EndDate"] rescue nil
      
      output = OpFormat.new                   #creating instance of OpFormat
      output.offer_type = "Lease"
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "GENESIS"
      output.model_details = "#{model_name}" + offer["ModelCode"].gsub(/\r|\n/,'') rescue nil
      output.emi = emi
      output.emi_months = emi_months
      output.down_payment = down_payment
      output.due_at_signing = details[7].scan(/\$\d\,\d+ due at lease signing/).first.gsub(" due at lease signing",'') rescue nil
      output.offer_start_date = offer_start_date.gsub(/(\d+)\/(\d+)\/(\d+)/,'\3-\2-\1') rescue nil
      output.offer_end_date = offer_end_date.gsub(/(\d+)\/(\d+)\/(\d+)/,'\3-\2-\1')  rescue nil
      output.security_deposit = OpFormat.parse_text(details[8].strip) rescue nil
      output.msrp = details[9].scan(/msrp.* \(/i).first.gsub(/MSRP|\(/,'').strip rescue nil
      output.mileage_charge = "$.#{details[18].scan(/^.*year,/).first}" rescue nil
      output.acquisition_fee = details[11].scan(/\$.*acquisition fee/).first.gsub(/acquisition fee/i,'').strip rescue nil
      output.disposition_fee = details[18].scan(/\$.*disposition fee/).first.gsub(/disposition fee/i,'').strip rescue nil
      output.tax_registration_exclusion = details[2].include?(" Excludes registration, tax,") ? "Y" : "N"
      output.title1 = title1
      output.offer1 = OpFormat.parse_text(offer["Name"]) rescue nil
      output.offer2 = offer2
      output.offer3 = offer3
      output.offer4 = offer4
      output.disclaimer1 = disclaimer
      lease_output_data << output
    }
    OpFormat.convert_to_json(lease_output_data , 'lease_data')   #Converting array of output objects in to json format
  end
  def extract_finance_data
    finance_output_data = []
    if !@response || @response["GetBrandSpecialOffersByZipResult"].empty?
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "GENESIS"
      @logger.info "No Finance data found for #{@zipcode}" 
      lease_output_data << output 
      return OpFormat.convert_to_json(finance_output_data , "lease_data")
    end
    @response["GetBrandSpecialOffersByZipResult"].each{|offers|
      if offers["Type"].include?("APR")
        apr_offers = offers["Name"].split(/\,/)
        if apr_offers.size > 1 && apr_offers[1].include?("months")
          apr_offers.each{|apr_offer|
            output = OpFormat.new
            output.apr_rate = apr_offer.scan(/\d+\.\d+\%/).first rescue nil
            output.emi_months = apr_offer.scan(/.*( \d+.*)months/).flatten.first.strip rescue nil
            model_info = offers["ModelName"].split('-') rescue nil
            model_name = model_info[0].upcase rescue nil
            year = model_info[1] rescue nil
            offer_start_date = offers["StartDate"] rescue nil
            offer_end_date = offers["EndDate"] rescue nil
            model_name = offers["ModelName"] rescue nil
            output.offer_type = "Finance"
            output.offer_type = "Other" if apr_offer.include?("Cash")
            output.zip = @zipcode                   #Populating instance with scraped data
            output.brand = "GENESIS"
            output.model_details = "#{model_name}" + offers["ModelCode"].gsub(/\r|\n/,'') rescue nil
            output.offer_start_date = offer_start_date.gsub(/(\d+)\/(\d+)\/(\d+)/,'\3-\2-\1')
            output.offer_end_date = offer_end_date.gsub(/(\d+)\/(\d+)\/(\d+)/,'\3-\2-\1') 
            output.title1 = "#{year} GENESIS #{model_name}" if !year.nil? && !model_name.nil?
            output.offer1 = OpFormat.parse_text(apr_offer) rescue nil
            output.disclaimer1 = OpFormat.parse_text(offers["DescriptionLong"].strip)
            finance_output_data << output
          }
        end
      end
    }
    return OpFormat.convert_to_json(finance_output_data , "finance_data")
  end
  
  def get_standard_headers
    @config["headers"].join(" ")
  end 
  
  def get_post_data
    @config["post_data"].gsub(/###ZIP###/, @zipcode.to_s)
  end
end



