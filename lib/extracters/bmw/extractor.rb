require_relative "../../../lib/extracters/base/base_extractor"
require_relative "../../../lib/utils/http_get"
require_relative "op_format.rb"
#require_relative "../../../lib/config/bmw.yml"
require "pry"
require "awesome_print"
require 'logging'
require 'logger'
require 'date'
class Extractor < BaseExtractor
  
  def initialize(make, zip)
    super(make, zip)
    @http_get = HttpGet.new(%w[shader shader shader squid squid shader], nil, {shuffle_prefs: true}, @logger)
  end
  
  def load_target_page()
    begin
      target_url = @config["target_page"] + @zipcode.to_s
      @logger.debug "Starting data extraction for zip #{@zipcode} at effective url #{target_url}"
      @response = @http_get.get(target_url, {json_res: true, curl_opts: [get_standard_headers]})
    rescue Exception => e
      @logger.error "Error occurred during loading target page"
      @logger.error e
    end
  end
  
  def set_zip_code()
    return nil
  end
  
  def extract_lease_data()
    lease_output_data = []
    if(@response.nil? || @response.empty?)
      output = OpFormat.new
      output.zip = @zipcode                  
      output.brand = "BMW"
      @logger.error "No lease data found for #{@zipcode}" 
      lease_output_data << output 
      return OpFormat.convert_to_json(lease_output_data, 'lease_data')
    end
    @response["offers"].each do |series, series_offers|
      series_offers.each do |offer|
        if(offer.has_key?("leaseOffer"))
          output = OpFormat.new
          output.zip = @zipcode
          output.brand = "BMW"
          output.offer_type = @config["xpaths"]["LEASE"]
          output.model_details = "Model Code - #{offer["code"]}"
          output.disclaimer1 =  OpFormat.parse_text(offer["leaseOffer"]["disclaimer"]) rescue nil
          short_disclaimer = OpFormat.parse_text(offer["leaseOffer"]["shortDisclaimer"]).gsub(/\.\.\./,'') rescue nil
          unless (output.disclaimer1.include?(short_disclaimer))
            output.disclaimer2 =  OpFormat.parse_text(offer["leaseOffer"]["shortDisclaimer"]) rescue nil
          end
          output.emi_months = output.disclaimer1[/per month for\s(\d+\s+\w+)/].gsub(/per month for\s/, '') rescue nil
          output.offer_end_date = Date.parse(output.disclaimer1[/Offer valid through\s+([\w\d]+\s+\d+[,\s]\s+\d+)/].gsub(/Offer valid through\s/, '')).to_s rescue nil
          output.disposition_fee = output.disclaimer1[/disposition fee of\s([\$\d]+)/].gsub(/disposition fee of\s/,'') rescue nil
          output.mileage_charge = output.disclaimer1[/([\$\d\.\/\w]+)\sover\s([\d\w\,]+)\smiles/] rescue nil
          output.emi = offer["leaseOffer"]["monthlyPayment"]["value"].gsub(/[^\d^\.]/, '').to_f rescue nil
          output.down_payment =  offer["leaseOffer"]["customerDownPayment"]["value"].gsub(/[^\d^\.]/, '').to_f rescue nil
          output.security_deposit = offer["leaseOffer"]["securityDeposit"]["value"].gsub(/[^\d^\.]/, '').to_f rescue nil
          output.acquisition_fee = offer["leaseOffer"]["aquisitionFee"]["value"].gsub(/[^\d^\.]/, '').to_f rescue nil
          output.due_at_signing = offer["leaseOffer"]["dueAtSigning"]["value"].gsub(/[^\d^\.]/, '').to_f rescue nil
          output.dealer_contribution =  offer["leaseOffer"]["dealerContribution"]["value"].gsub(/[^\d^\.]/, '').to_f rescue nil
          output.msrp = offer["leaseOffer"]["msrp"]
          output.title1 = offer["year"].to_i.to_s + " " + offer["modelDescription"]
          output.title2 = offer["promotionTop"]
          output.title3 = offer["leaseOffer"]["description"]
          output.offer1 = offer["leaseOffer"]["monthlyPayment"]["unit"] + offer["leaseOffer"]["monthlyPayment"]["value"] + " per month for " + output.emi_months
          output.offer2 = offer["leaseOffer"]["information"][0]
          output.offer3 = offer["leaseOffer"]["customerDownPayment"]["unit"] + offer["leaseOffer"]["customerDownPayment"]["value"] + " Down payment" 
          output.offer4 = offer["leaseOffer"]["securityDeposit"]["unit"] + offer["leaseOffer"]["securityDeposit"]["value"] + " security deposit"
          output.offer5 = offer["leaseOffer"]["aquisitionFee"]["unit"] + offer["leaseOffer"]["aquisitionFee"]["value"] + " acquisition fee"
          output.offer6 = offer["leaseOffer"]["dueAtSigning"]["unit"] + offer["leaseOffer"]["dueAtSigning"]["value"] + " Due at Signing"
          output.offer7 = offer["leaseOffer"]["dealerContribution"]["unit"] + offer["leaseOffer"]["dealerContribution"]["value"] + " dealer contribution"
          output.model_details = offer["modelDescription"]
          output.tax_registration_exclusion = output.disclaimer1.include?("Tax, title, license and registration fees are additional fees due at signing") ? "Y" : nil rescue nil
          lease_output_data << output
        end        
      end
    end
    @logger.debug "Total number of lease specials offer found is #{lease_output_data.size}"
    return OpFormat.convert_to_json(lease_output_data, "lease_data")
  rescue Exception => e
    @logger.error "Error while extracting data from individual lease specials page"
    @logger.error e
    return nil
  end
  
  def extract_finance_data()
    finance_output_data = []
    if(@response.nil? || @response.empty?)
      output = OpFormat.new
      output.zip = @zipcode                  
      output.brand = "BMW"
      @logger.error "No finance data found for #{@zipcode}" 
      finance_output_data << output 
      return OpFormat.convert_to_json(finance_output_data, 'finance_data')
    end
    @response["offers"].each do |series, series_offers|
      series_offers.each do |offer|
        if(offer.has_key?("financeOffer"))
          output = OpFormat.new
          output.zip = @zipcode
          output.brand = "BMW"
          output.offer_type = @config["xpaths"]["FINANCE"]
          output.model_details = offer["modelDescription"]
          description = OpFormat.parse_text(offer["financeOffer"]["description"]) rescue nil
          output.disclaimer1 = OpFormat.parse_text(offer["financeOffer"]["disclaimer"]) rescue nil
          short_disclaimer = OpFormat.parse_text(offer["financeOffer"]["shortDisclaimer"]).gsub(/\.\.\./,'') rescue nil
          unless (output.disclaimer1.include?(short_disclaimer))
            output.disclaimer2 =  OpFormat.parse_text(offer["financeOffer"]["shortDisclaimer"]) rescue nil
          end
          output.emi_months = description[/.*contracts upto\s+([\w\d]+\s+\d+[,\s]\s+\d+)/].gsub(/.*contracts upto\s/, '') rescue nil
          output.offer_end_date = Date.parse(description[/credits valid through\s([\w\d\,\s]+)/].gsub(/credits valid through/, '')).to_s rescue nil
          output.msrp = offer["price"]
          output.title1 = offer["year"].to_i.to_s + " " + offer["modelDescription"]
          output.title2 = offer["promotionTop"]
          output.title3 = description
          output.offer1 = 'Finance at as low as ' +offer["financeOffer"]["apr1"]["value"] + offer["financeOffer"]["apr1"]["unit"]
          output.apr_rate = offer["financeOffer"]["apr1"]["value"]
          output.emi_months = description.scan(/APR financing for contracts up to (\d+\smonths)/).flatten[0]
          output.offer2 = 'Also available:' + offer["financeOffer"]["information"][0] unless offer["financeOffer"]["information"][0].nil? || offer["financeOffer"]["information"][0].empty? 
          finance_output_data << output
        end        
      end
    end
    @logger.debug "Total number of finance offers found is #{finance_output_data.size}"
    return OpFormat.convert_to_json(finance_output_data, "finance_data")
  rescue Exception => e
    @logger.error "Error while extracting data from individual finance details page"
    @logger.error e
    return nil
  end
 
  
  def get_standard_headers
   @config["headers"].join(" ")
  end
end