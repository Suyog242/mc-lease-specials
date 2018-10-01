require 'json'
require 'ap'
require_relative "../../../lib/extracters/base/base_extractor"
require_relative "../../../lib/utils/http_get.rb"
require_relative "op_format.rb"

class Extractor < BaseExtractor
  def initialize(make, zipcode)
    super(make, zipcode)
    @http_get = HttpGet.new(%w[shader shader shader], nil, {shuffle_prefs: true}, @logger)
  end
  
  def load_target_page()
    @target_url = @config["target_page"].gsub("###zipcode###",@zipcode.to_s)
    @logger.info "Loading page #{@target_url}"
    @response = JSON.parse(@http_get.get(@target_url, {json_res: true, curl_opts: [get_standard_headers]}).to_json)
  end
  
  def set_zip_code()
    
  end
  
  def lease_data(_offer)
    output = OpFormat.new
    output.zip,output.brand,output.offer_type = @zipcode,"ACURA","Lease"                  
    output.model_details = "Model Id - #{_offer["ModelId"]}" rescue nil
    output.emi = _offer["LeasePaymentInfo"]["BaseMonthlyPayment"] rescue nil
    output.emi_months = _offer["LeasePaymentInfo"]["TermMonths"] rescue nil
    output.due_at_signing = _offer["LeasePaymentInfo"]["TotalDueAtSigning"] rescue nil
    output.acquisition_fee = _offer["SpecialDescription"].scan(/\d+\sacquisition/)[0].split(" ")[0] rescue nil
    output.msrp = _offer["SpecialDescription"].scan(/MSRP\s\$\d+,\d+/)[0].split("$")[1].to_s rescue nil
    output.offer_start_date = _offer["StartDate"] rescue nil
    output.offer_end_date = _offer["EndDate"] rescue nil
    output.security_deposit = (_offer["ShortDisclaimer"].include?"no security deposit")? "0":nil rescue nil
    output.title1 = _offer["SalesProgramTypeDescription"] rescue nil
    output.title2 = "Expires #{_offer["EndDate"]}"
    output.title3 = _offer["SalesProgramName"] rescue nil
    output.offer1 = "#{_offer["SpecialShortDescription"].to_s.gsub(/months(.*)/,"")}months" rescue nil
    output.offer2 = _offer["SpecialShortDescription"].to_s.gsub(/(.*)months./,"").strip rescue nil
    output.offer3 = _offer["ShortDisclaimer"] rescue nil
    output.mileage_charge = _offer["TermsAndConditions"] rescue nil
    output.tax_registration_exclusion = (_offer["ShortDisclaimer"].include?"Excludes")? "Y":nil rescue nil
    output.disclaimer1 = _offer["SpecialDescription"] rescue nil
    output.disclaimer2 = _offer["TermsAndConditions"] rescue nil
    return output
  end
  
  def apr_data(_offer)
    output = OpFormat.new
    output.zip,output.brand,output.offer_type = @zipcode,"ACURA","Finance"
    output.model_details = _offer["ModelId"] rescue nil
    output.offer_start_date = _offer["StartDate"] rescue nil
    output.offer_end_date = _offer["EndDate"] rescue nil
    output.security_deposit = nil
    output.apr_rate = _offer["SpecialShortDescription"].scan(/\d+.\d+%/).join("|").gsub(/%/,"") rescue nil
    output.emi_months = _offer["SpecialShortDescription"].scan(/\d+.\d+ months/).join("|") rescue nil 
    output.title1 = _offer["SalesProgramTypeDescription"] rescue nil
    output.title2 = "Expires #{_offer["EndDate"]}"
    output.title3 = _offer["SalesProgramName"] rescue nil
    output.offer1 = _offer["SpecialShortDescription"].to_s.split(" or ")[0] rescue nil
    output.offer2 = _offer["SpecialShortDescription"].to_s.split(" or ")[1] rescue nil
    output.offer3 = _offer["ShortDisclaimer"] rescue nil
    output.disclaimer1 = _offer["SpecialDescription"] rescue nil
    output.disclaimer2 = _offer["TermsAndConditions"].gsub(/<br\s*\/?>/, '') rescue nil
    return output
  end
  
  def other_data(_offer)
    output = OpFormat.new
    output.zip,output.brand,output.offer_type = @zipcode,"ACURA","Other"
    output.offer_start_date = _offer["StartDate"] rescue nil
    output.offer_end_date = _offer["EndDate"] rescue nil
    output.security_deposit = nil
    output.cashback_amount = _offer["OfferAmount"].to_s rescue nil
    output.title1 = _offer["SalesProgramTypeDescription"] rescue nil
    output.title2 = "Expires #{_offer["EndDate"]}"
    output.title3 = _offer["SalesProgramName"] rescue nil
    output.offer1 = "$#{_offer["OfferAmount"].to_i}" rescue nil
    output.offer2 = _offer["SpecialShortDescription"].to_s rescue nil
    output.offer3 = OpFormat.parse_text(_offer["ShortDisclaimer"]) rescue nil
    output.disclaimer1 = OpFormat.parse_text(_offer["SpecialDescription"].gsub(/<("[^"]*"|'[^']*'|[^'">])*>/, '')) rescue nil
    output.disclaimer2 = OpFormat.parse_text(_offer["TermsAndConditions"].gsub(/<("[^"]*"|'[^']*'|[^'">])*>/, '')) rescue nil 
    return output
  end
  
  def extract_lease_data()
    lease_output_data = []
    @response["Offers"].each { |_offer| lease_output_data << lease_data(_offer)  if _offer["SalesProgramType"] == "Lease" }
    @logger.info "Total #{lease_output_data.size} records found for #{@zipcode}" 
    return OpFormat.convert_to_json(lease_output_data, "lease_data") 
  end
  
  def extract_finance_data()
    finance_output_data = []
    @response["Offers"].each do |_offer|
      sale_type = _offer["SalesProgramType"] rescue ""
      finance_output_data << apr_data(_offer) if sale_type == "Finance"
      finance_output_data << other_data(_offer) if (sale_type == "HCPV" || sale_type == "Military" || sale_type == "Conquest")
    end
    @logger.info "Total #{finance_output_data.size} records found for #{@zipcode}" 
    return OpFormat.convert_to_json(finance_output_data, "finance_data") 
  end
  
  def get_standard_headers
    @config["headers"].join(" ")
  end 
end



