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
    output.zip,output.brand,output.offer_type = @zipcode,"HONDA","Lease"                  
    output.model_details = OpFormat.parse_text("Model Id - #{_offer["ModelId"]}") rescue nil
    output.emi = _offer["LeasePaymentInfo"]["BaseMonthlyPayment"] rescue nil
    output.emi_months = _offer["LeasePaymentInfo"]["TermMonths"] rescue nil
    output.due_at_signing = _offer["LeasePaymentInfo"]["TotalDueAtSigning"] rescue nil
    output.acquisition_fee = _offer["SpecialDescription"].scan(/\d+\sacquisition/)[0].split(" ")[0] rescue nil
    output.msrp = _offer["SpecialDescription"].scan(/MSRP\s\$\d+,\d+/)[0].split("$")[1].to_s rescue nil
    output.offer_start_date = _offer["StartDate"] rescue nil
    output.offer_end_date = _offer["EndDate"] rescue nil
    output.security_deposit = (_offer["ShortDisclaimer"].include?"no security deposit")? "0":nil rescue nil
    output.title1 = OpFormat.parse_text(_offer["SalesProgramTypeDescription"]) rescue nil
    output.title2 = "Expires #{_offer["EndDate"]}"
    output.title3 = OpFormat.parse_text(_offer["SalesProgramName"]) rescue nil
    output.offer1 = OpFormat.parse_text("#{_offer["SpecialShortDescription"].to_s.gsub(/months(.*)/,"")}months") rescue nil
    output.offer2 = OpFormat.parse_text(_offer["SpecialShortDescription"].to_s.gsub(/(.*)months./,"").strip) rescue nil
    output.offer3 = OpFormat.parse_text(_offer["ShortDisclaimer"]) rescue nil
    #output.mileage_charge = OpFormat.parse_text(_offer["TermsAndConditions"]) rescue nil
    output.tax_registration_exclusion = (_offer["ShortDisclaimer"].include?"Excludes")? "Y":nil rescue nil
    output.disclaimer1 = OpFormat.parse_text(_offer["SpecialDescription"].gsub(/<br\s*\/?>/, '')) rescue nil
    output.mileage_charge = _offer["SpecialDescription"].gsub(/<br\s*\/?>/, '').scan(/excessive wear\/tear and [\d\/\w\s\,\.\$\¢]+/).flatten[0] unless output.disclaimer1.nil?
    #output.disclaimer2 = OpFormat.parse_text(_offer["TermsAndConditions"]) rescue nil
    return output
  end
  
  def apr_data(_offer)
    output = OpFormat.new
    output.zip,output.brand,output.offer_type = @zipcode,"HONDA","Finance"
    output.model_details = OpFormat.parse_text(_offer["ModelId"]) rescue nil
    output.offer_start_date = _offer["StartDate"] rescue nil
    output.offer_end_date = _offer["EndDate"] rescue nil
    output.security_deposit = nil
    output.apr_rate = _offer["SpecialShortDescription"].scan(/\d+.\d+%/).join("|").gsub(/%/,"") rescue nil
    output.emi_months = _offer["SpecialShortDescription"].scan(/\d+.\d+ months/).join("|") rescue nil 
    output.title1 = OpFormat.parse_text(_offer["SalesProgramTypeDescription"]) rescue nil
    output.title2 = "Expires #{_offer["EndDate"]}"
    output.title3 = OpFormat.parse_text(_offer["SalesProgramName"]) rescue nil
    output.offer1 = OpFormat.parse_text(_offer["SpecialShortDescription"].to_s.split(" or ")[0]) rescue nil
    output.offer2 = OpFormat.parse_text(_offer["SpecialShortDescription"].to_s.split(" or ")[1]) rescue nil
    output.offer3 = OpFormat.parse_text(_offer["ShortDisclaimer"]) rescue nil
    output.disclaimer1 = OpFormat.parse_text(_offer["SpecialDescription"].gsub(/<br\s*\/?>/, '')) rescue nil
    output.disclaimer2 = OpFormat.parse_text(_offer["TermsAndConditions"].gsub(/<br\s*\/?>/, '')) rescue nil
    return output
  end
  
  def other_data(_offer)
    output = OpFormat.new
    output.zip,output.brand,output.offer_type = @zipcode,"HONDA","Other"
    output.offer_start_date = _offer["StartDate"] rescue nil
    output.offer_end_date = _offer["EndDate"] rescue nil
    output.security_deposit = nil
    output.cashback_amount = _offer["OfferAmount"].to_s rescue nil
    output.title1 = OpFormat.parse_text(_offer["SalesProgramTypeDescription"]) rescue nil
    output.title2 = "Expires #{_offer["EndDate"]}"
    output.title3 = OpFormat.parse_text(_offer["SalesProgramName"]) rescue nil
    output.offer1 = "$#{_offer["OfferAmount"].to_i}" rescue nil
    output.offer2 = OpFormat.parse_text(_offer["SpecialShortDescription"].to_s) rescue nil
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


# Old Implementation using HTML scraping and Xpaths


#require_relative "../../../lib/extracters/base/base_extractor"
#require_relative "../../../lib/utils/http_get"
#require_relative "op_format.rb"
#require "pry"
#require "awesome_print"
#require 'logging'
#require 'logger'
#require 'nokogiri'
#class Extractor < BaseExtractor
#  
#  def initialize(make, zip)
#    super(make, zip)
#    @http_get = HttpGet.new(%w[shader shader shader squid squid shader], nil, {shuffle_prefs: true}, @logger)
#  end
#  
#  def load_target_page()
#    begin
#      target_url = @config["target_page"] + @zipcode.to_s
#      @logger.debug "Starting lease specials extraction for zip #{@zipcode} with effective url of #{target_url}"
#      @response = Nokogiri::HTML(@http_get.get(target_url, {curl_opts: [get_standard_headers]}))
#    rescue Exception => e
#      @logger.error "Error ocurred while loading target page"
#      @logger.error e
#    end
#  end
#  
#  def set_zip_code()
#    return nil
#  end
#  
#  def extract_lease_data()
#    lease_output_data = []
#    if(@response.nil?)
#      output = OpFormat.new  
#      output.zip = @zipcode                  
#      output.brand = "HONDA"
#      @logger.error "No lease data found for #{@zipcode}" 
#      lease_output_data << output 
#      return OpFormat.convert_to_json(lease_output_data, 'lease_data')
#    end
#    @X = @config['xpaths']
#    models = @response.xpath("#{@X['models']}")
#    @logger.debug "Number of models with lease specials offer found are #{models.size}"
#    models.each do |model|
#      trims = model.xpath(".#{@X['trims']}")
#      trims.each do |trim|
#        output = OpFormat.new
#        output.zip = @zipcode
#        output.title1 = OpFormat.parse_text(model.xpath(".#{@X['title1']}").text.strip)
#        output.model_details = output.title1
#        output.brand = "HONDA"
#        output.offer_type = @X["LEASE"]
#        output.title2 = OpFormat.parse_text(model.xpath(".#{@X['title2']}").text)
#        output.title3 = OpFormat.parse_text(trim.xpath(".#{@X['title3']}").text.strip)
#        output.offer1 = OpFormat.parse_text(trim.xpath(".#{@X['offer1']}").text.strip)
#        output.offer2 = OpFormat.parse_text(trim.xpath(".#{@X['offer2']}").text.strip)
#        output.offer3 = OpFormat.parse_text(trim.xpath(".#{@X['offer3']}").text)
#        disclaimer_link = trim.xpath(".#{@X['disclaimer_link']}").text.gsub(/\#/,'')
#        #@disclaimer1 = @response.xpath("//div[@id='#{disclaimer_link}']//div[@class='desc']").text.gsub(/\r\n|\n\r/,'').gsub(/\s{2,}/,' ')
#        output.disclaimer1 = OpFormat.parse_text(@response.xpath("#{@X['disclaimer'].gsub(/---disclaimer_link---/,disclaimer_link)}").text.strip.gsub(/\s{2,}/,' '))
#        output.acquisition_fee = output.disclaimer1[/([\$\d\.\,]+)\sacquisition fee/].gsub(/\sacquisition fee/,'') rescue nil
#        offer_figures = output.offer1.scan(/[\d\.\,]+/).select{|x| x.match(/\d/)} rescue nil
#        output.emi = offer_figures[0].gsub(/[^\d^\.]/, '').to_f rescue nil
#        output.emi_months = offer_figures[1].to_i rescue nil
#        output.down_payment = offer_figures[2].gsub(/[^\d^\.]/, '').to_f rescue nil
#        output.due_at_signing = output.offer1.scan(/[\$\d\.\,]+/).select{|x| x.match(/\d/)}.flatten[2] rescue nil
#        offer_dates = output.disclaimer1.scan(/available from ([\w\d]+\s[\d+]\,\s\d+) through (\w+\s\d+\,\s\d+)/).flatten rescue nil
#        output.offer_start_date = offer_dates[0] rescue nil
#        output.offer_end_date = offer_dates[1] rescue nil
#        output.msrp = output.disclaimer1.scan(/MSRP\s+(\$[\d\.\,]+)/).flatten[0].gsub(/[^\d^\.]/, '').to_f rescue nil
#        output.mileage_charge = output.disclaimer1[/(?<=excessive wear\/tear and)(.*)(?=or more.)/] + "or more" rescue nil
#        output.tax_registration_exclusion = output.disclaimer1.include?("excludes tax, license, title, registration") ? "Y" : "N"
#        lease_output_data << output
#      end
#    end
#    @logger.debug "Total number of lease specials offer found for all models and trims is #{lease_output_data.size}"
#    return OpFormat.convert_to_json(lease_output_data, 'lease_data')
#  rescue Exception => e
#    @logger.error "Error while extracting data from individual lease specials page"
#    @logger.error e
#    return nil
#  end
#  
#  def extract_finance_data()
#    finance_output_data = []
#    if(@response.nil?)
#      output = OpFormat.new  
#      output.zip = @zipcode                  
#      output.brand = "HONDA"
#      @logger.error "No lease data found for #{@zipcode}" 
#      finance_output_data << output 
#      return OpFormat.convert_to_json(finance_output_data, 'finance_data')
#    end
#    @X = @config['xpaths']
#    models = @response.xpath("#{@X['models']}")
#    @logger.debug "Number of models with local offer found are #{models.size}"
#    models.each do |model|
#      trims = model.xpath(".#{@X['finance_trims']}")
#      trims.each do |trim|
#        output = OpFormat.new
#        output.zip = @zipcode
#        output.title1 = OpFormat.parse_text(model.xpath(".#{@X['title1']}").text.strip)
#        output.model_details = output.title1
#        output.brand = "HONDA"
#        output.offer_type = @X["FINANCE"]
#        output.title2 = OpFormat.parse_text(model.xpath(".#{@X['finance_title2']}").text)
#        output.title3 = OpFormat.parse_text(trim.xpath(".#{@X['title3']}").text.strip)
#        output.offer1 = OpFormat.parse_text(trim.xpath(".#{@X['offer1']}").text.strip)
#        apr_offer_array = output.offer1.scan(/([\d\.\,\-]+)/).flatten.select{|x| x != "." }
#        if(apr_offer_array.length > 2) 
#          output.apr_rate = apr_offer_array[0] + "|" + apr_offer_array[2]
#          output.emi_months = apr_offer_array[1] + " months|"+ apr_offer_array[3] +" months"
#        else
#          output.apr_rate = apr_offer_array[0]
#          output.emi_months = apr_offer_array[1]
#        end
#        output.offer2 = OpFormat.parse_text(trim.xpath(".#{@X['offer2']}").text.strip)
#        output.offer3 = OpFormat.parse_text(trim.xpath(".#{@X['offer3']}").text)
#        disclaimer_link = trim.xpath(".#{@X['disclaimer_link']}").text.gsub(/\#/,'')
#        #@disclaimer1 = @response.xpath("//div[@id='#{disclaimer_link}']//div[@class='desc']").text.gsub(/\r\n|\n\r/,'').gsub(/\s{2,}/,' ')
#        output.disclaimer1 = OpFormat.parse_text(@response.xpath("#{@X['disclaimer'].gsub(/---disclaimer_link---/,disclaimer_link)}").text.strip.gsub(/\s{2,}/,' '))
#        offer_dates = output.disclaimer1.scan(/from ([\w\d]+\s[\d+]\,\s\d+) through (\w+\s\d+\,\s\d+)/).flatten
#        output.offer_start_date = offer_dates[0]
#        output.offer_end_date = offer_dates[1]
#        finance_output_data << output
#      end
#    end
#    @logger.debug "Total number of finance offer found for all models and trims is #{finance_output_data.size}"
#    return OpFormat.convert_to_json(finance_output_data, 'finance_data')
#  rescue Exception => e
#    @logger.error "Error while extracting data from individual finance offers page"
#    @logger.error e
#    return nil
#  end
#  
#  
#  def get_standard_headers
#   @config["headers"].join(" ")
#  end
#end


