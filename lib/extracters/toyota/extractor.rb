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
    output.zip,output.brand,offer_type = @zipcode,"TOYOTA","Lease"                  
    output.offer_type = offer_type 
    output.model_details = "Model Code - #{_offer["seriesList"]["series"]["includedModels"]["includedModel"].map {|_model| _model["code"]}.join(",")}" rescue nil
    output.emi = _offer["lease"]["tiers"]["tier"][0]["term"][0]["monthlyPayment"] rescue nil
    output.emi_months = _offer["lease"]["tiers"]["tier"][0]["term"][0]["duration"] rescue nil
    output.down_payment = _offer[offer_type.downcase]["downPayment"] rescue nil
    output.due_at_signing = _offer["lease"]["tiers"]["tier"][0]["term"][0]["dueAtSigningAmount"] rescue nil
    output.offer_start_date = _offer["startDate"] rescue nil
    output.offer_end_date = _offer["endDate"] rescue nil
    output.security_deposit = _offer["lease"]["tiers"]["tier"][0]["term"][0]["securityDeposit"] rescue nil
    output.msrp = _offer[offer_type.downcase]["vehicleSellingPrice"].to_s rescue nil
    output.acquisition_fee = _offer[offer_type.downcase]["acquisitionFee"] rescue nil
    output.disposition_fee = _offer[offer_type.downcase]["dispositionFee"] rescue nil
    output.title1 = offer_type rescue nil
    output.title2 = "#{_offer["seriesList"]["series"]["year"]} #{_offer["seriesList"]["series"]["name"]}" rescue nil
    output.title3 = _offer["seriesList"]["series"]["includedModels"]["includedModel"].map {|_model| _model["name"]}.join(",") rescue nil
    output.title4 = "EXP. #{_offer["endDate"]}" rescue nil
    output.title5 = "$#{output.emi} per month" rescue nil
    output.title6 = "#{output.emi_months} months" rescue nil
    output.title7 = "$#{output.due_at_signing} due at signing" rescue nil
    output = offer_data(_offer, output)
    output.disclaimer1 = OpFormat.parse_text(_offer["disclaimers"]["disclaimer"][0]) rescue nil
    output.disclaimer2 = OpFormat.parse_text(_offer["additionalDisclaimers"]) rescue nil
    output.disclaimer2 = OpFormat.parse_text(_offer["disclaimers"]["disclaimer"][1]) if (output.disclaimer2.nil? || output.disclaimer2.empty?) rescue nil
    output.tax_registration_exclusion = (_offer["disclaimers"]["disclaimer"][0].include?"Excludes official fees")? "Y":nil rescue nil
    output.mileage_charge = output.disclaimer1.scan(/\$\d+\.\d+.*per year/)[0] rescue nil
    output.mileage_charge = output.disclaimer1.scan(/\$\.\d+.*year/)[0] if output.mileage_charge.nil? rescue nil
    return output
  end
  
  def cash_data(_offer)
    output = OpFormat.new
    output = finance_fields_data(_offer, output)
    output.cashback_amount = _offer[_offer["offerType"].downcase]["cashAmount"] rescue nil
    output.title5 = "$#{_offer[_offer["offerType"].downcase]["cashAmount"]} Cash Back" rescue nil 
    output.offer_type = "Other" 
    return output
  end
  
  def apr_data(_offer)
    final_apr_data = []
    _offer[_offer["offerType"].downcase]["tiers"]["tier"][0]["term"].each_index do |index|
      output = OpFormat.new
      output = finance_fields_data(_offer, output, index)
      output.title5 = "#{_offer[_offer["offerType"].downcase]["tiers"]["tier"][0]["term"][index]["rate"]}%APR" rescue nil 
      output.title6 = "#{output.emi_months} months" rescue nil 
      output.apr_rate = _offer[_offer["offerType"].downcase]["tiers"]["tier"][0]["term"][index]["rate"] rescue nil 
      output.offer_type = "Finance" 
      final_apr_data << output
    end
    return final_apr_data
  end
  
  def finance_fields_data(_offer, output, index = 0)
    output.zip,output.brand = @zipcode,"TOYOTA"    
    output.model_details = "Model Code - #{_offer["seriesList"]["series"]["includedModels"]["includedModel"].map {|_model| _model["code"]}.join(",")}" rescue nil
    offer_type = _offer["offerType"] rescue nil
    output.emi_months = _offer[offer_type.downcase]["tiers"]["tier"][0]["term"][index]["duration"] rescue nil
    output.down_payment = _offer[offer_type.downcase]["downPayment"] rescue nil
    output.offer_start_date = _offer["startDate"] rescue nil
    output.offer_end_date = _offer["endDate"] rescue nil
    output.security_deposit = _offer[offer_type.downcase]["tiers"]["tier"][0]["term"][index]["securityDeposit"] rescue nil
    output.title1 = _offer["offerType"] rescue nil
    output.title2 = "#{_offer["seriesList"]["series"]["year"]} #{_offer["seriesList"]["series"]["name"]}" rescue nil
    output.title3 = _offer["seriesList"]["series"]["includedModels"]["includedModel"].map {|_model| _model["name"]}.join(",") rescue nil
    output.title4 = "EXP. #{_offer["endDate"]}" rescue nil
    output = offer_data(_offer, output)
    output = disclaimer_data(_offer, output)
    return output
  end
  
  def other_data(_offer)
    output = OpFormat.new
    output.zip,output.brand,output.offer_type = @zipcode,"TOYOTA","Other"
    output.cashback_amount = _offer["multivehicle"]["cashAmount"] rescue nil
    output.offer_start_date = _offer["startDate"] rescue nil
    output.offer_end_date = _offer["endDate"] rescue nil
    output.title1 = "Other"
    output.title2 = _offer["title"] rescue nil
    output.title4 = "EXP. #{_offer["endDate"]}" rescue nil
    output.title5 = "$#{_offer["multivehicle"]["cashAmount"]} #{_offer["multivehicle"]["subTypeLabels"]}" rescue nil 
    output = offer_data(_offer, output)
    output = disclaimer_data(_offer, output)
    return output
  end
  
  def offer_data(_offer, output)
    output.offer1 = OpFormat.parse_text(_offer["description"]) rescue nil
    output.offer2 = OpFormat.parse_text(_offer["bullets"]["bullet"][0]["text"]) rescue nil
    output.offer3 = OpFormat.parse_text(_offer["bullets"]["bullet"][1]["text"]) rescue nil
    output.offer4 = OpFormat.parse_text(_offer["bullets"]["bullet"][2]["text"]) rescue nil
    output.offer5 = OpFormat.parse_text(_offer["bullets"]["bullet"][3]["text"]) rescue nil
    output.offer6 = OpFormat.parse_text(_offer["bullets"]["bullet"][4]["text"]) rescue nil
    output.offer7 = OpFormat.parse_text(_offer["bullets"]["bullet"][5]["text"]) rescue nil
    output.offer8 = OpFormat.parse_text(_offer["bullets"]["bullet"][5]["text"]) rescue nil
    return output
  end
  
  def disclaimer_data(_offer, output)
    if !_offer["disclaimers"]["disclaimer"][0].nil?
      output.disclaimer1 = OpFormat.parse_text(_offer["disclaimers"]["disclaimer"][0]) rescue nil
      output.disclaimer2 = OpFormat.parse_text(_offer["additionalDisclaimers"]) rescue nil
      output.disclaimer2 =  OpFormat.parse_text(_offer["disclaimers"]["disclaimer"][1]) if (output.disclaimer2.nil? || output.disclaimer2.empty?) rescue nil
      output.tax_registration_exclusion = (_offer["disclaimers"]["disclaimer"][0].include?"Excludes official fees")? "Y":nil rescue nil
    else
      output.disclaimer1 = OpFormat.parse_text(_offer["additionalDisclaimers"]) rescue nil
      output.disclaimer2 = OpFormat.parse_text(_offer["additionalRestrictions"]) rescue nil
    end
    return output
  end
  
  def extract_lease_data()
    lease_output_data = []
    if(!@response["error"].empty?)
      output = OpFormat.new  
      output.zip,output.brand = @zipcode,"TOYOTA"                   
      @logger.info "No lease data found for #{@zipcode}" 
      return OpFormat.convert_to_json(lease_output_data << output,"lease_data")
    end
    @response["offerBundle"]["offers"].each { |_offer| lease_output_data << lease_data(_offer) if !_offer["lease"].nil? }
    @logger.info "Total #{lease_output_data.size} records found for #{@zipcode}" 
    return OpFormat.convert_to_json(lease_output_data, "lease_data")   #Converting array of output objects in to json format
  end
  
  def extract_finance_data()
    finance_output_data = []
    if(!@response["error"].empty?)
      output = OpFormat.new  
      output.zip,output.brand = @zipcode,"TOYOTA"  
      @logger.info "No finance data found for #{@zipcode}" 
      return OpFormat.convert_to_json(finance_output_data << output , "finance_data")
    end
    @response["offerBundle"]["offers"].each do |_offer|
      finance_output_data << cash_data(_offer) if !_offer["cash"].nil?
      apr_data(_offer).each {|_record| finance_output_data << _record} if !_offer["apr"].nil?
      finance_output_data << other_data(_offer) if !_offer["multivehicle"].nil?
    end
    @logger.info "Total #{finance_output_data.size} records found for #{@zipcode}" 
    return OpFormat.convert_to_json(finance_output_data, "finance_data") 
  end
  
  def get_standard_headers
    @config["headers"].join(" ")
  end 
end



