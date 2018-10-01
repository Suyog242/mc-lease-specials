require_relative "../../../lib/extracters/base/base_extractor"
require_relative "../../../lib/utils/http_get"
require 'nokogiri'
require 'uri'
require 'json'
require_relative "op_format.rb"

class Extractor < BaseExtractor
  def initialize(make, zipcode)
    super(make, zipcode)
    @http_get = HttpGet.new(%w[shader shader shader shader shader], nil, {shuffle_prefs: true}, @logger)
    @zipcode = zipcode
    @cookie_index = 0
  end
  
  def load_target_page()
    @target_url = @config["target_page"]
    @logger.debug "loding #{@target_url} page"
    offer_page_url = URI.join("#{@target_url}".gsub("###zipcode###",@zipcode.to_s)).to_s
    response = @http_get.get(offer_page_url, {json_res: false, curl_opts: [get_offer_page_headers()]})
    doc = Nokogiri::HTML(response)
    @parameters = doc.xpath(".//div[contains(@class,'offer-lease')]")
  end
  
  def set_zip_code()
    
  end
  
  def extract_lease_data()
    lease_output_data = []
    output = OpFormat.new
    @parameters.each do |offer|
      output = OpFormat.new
      title1 = offer.xpath("#{@config["xpaths"]["title_1"]}").text().strip
      next if title1 != "Lease"
      output.title1 = title1
      output.title2 = offer.xpath("#{@config["xpaths"]["title_2"]}").text().strip
      output.model_details = output.title2
      output.title3 = offer.xpath(".//h3").text().strip.gsub("\r\n"," ")
      offer_1_price = offer.xpath("#{@config["xpaths"]["offer_1"]}").text().strip
      output.emi = offer_1_price
      offer_1_months = offer.xpath("#{@config["xpaths"]["offer_1_months"]}").text().strip
      output.emi_months = offer_1_months
      output.offer1 = "#{offer_1_price}"+" for #{offer_1_months} months"
      output.offer_type = "Lease"
      offer_2_price = offer.xpath("#{@config["xpaths"]["offer_2"]}").text().strip
      offer_2_months = offer.xpath("#{@config["xpaths"]["offer_2_months"]}").text().strip
      output.offer2 = "#{offer_2_price}"+" #{offer_2_months}"
      output.due_at_signing = offer_2_price
      output.offer3 = offer.xpath(".//p").text().strip.split("\r\n\r\n")[0]
      output.security_deposit = output.offer3.split(".")[2].strip
      output.offer_end_date = offer.xpath(".//p[contains(@class,'terms')]").text.split("\r\n\r\n")[0].split(".")[0].strip.split(" ")[1]
      output.tax_registration_exclusion = (output.offer3.include?"Excludes official fees, taxes and dealer charges")? "Y":"N" rescue nil
      output.mileage_charge = output.disclaimer1.match("\\W\\d+\.\\d+ per mile").to_s rescue nil
      disclaimer = JSON.parse(offer.xpath("#{@config["xpaths"]["Disclaimer1"]}").first.value)
      output.disclaimer1 = OpFormat.parse_text(disclaimer[0]["body"])
      output.brand = "LEXUS"
      output.zip = @zipcode 
      lease_output_data << output
    end
    
    if(lease_output_data.size == 0)
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "LEXUS"
      output.offer_type = "Lease"
      @logger.info "No lease data found for #{@zipcode}"
      lease_output_data << output 
    end
    return OpFormat.convert_to_json(lease_output_data,"lease_data")
  end
  
  
  
  def disclamer_data(output, offer)
    disclaimer = JSON.parse(offer.xpath("#{@config["xpaths"]["Disclaimer1"]}").first.value)
      output.disclaimer1 = OpFormat.parse_text(disclaimer[0]["body"])
  end
  
  def extract_finance_data()
    lease_output_data = []
    output = OpFormat.new
    @parameters.each do |offer|
      output = OpFormat.new
      title1 = offer.xpath("#{@config["xpaths"]["title_1"]}").text().strip
      next if title1 != "Finance"
      output.title1 = title1
      output.offer_type = "Finance"
      output.title2 = offer.xpath("#{@config["xpaths"]["title_2"]}").text().strip
      output.model_details = output.title2
      output.title3 = offer.xpath(".//h3").text().strip.gsub("\r\n"," ")
      offer_1_price = offer.xpath("#{@config["xpaths"]["offer_1"]}").text().strip
      output.apr_rate = offer_1_price
      offer_1_months = offer.xpath("#{@config["xpaths"]["offer_1_months"]}").text().strip
      output.emi_months = offer_1_months
      output.offer1 = "#{offer_1_price}"+" for #{offer_1_months} months"
      output.offer2 = offer.xpath(".//p").text().strip.split("\r\n\r\n")[0]
      offer_enddate = offer.xpath(".//p[contains(@class,'terms')]").text.split("\r\n\r\n")[0].split(".")[0].strip.split(" ")[1]
      output.offer_end_date = "#{offer_enddate.split("/")[2]}/#{offer_enddate.split("/")[1]}/#{offer_enddate.split("/")[0]}"
      disclaimer = JSON.parse(offer.xpath("#{@config["xpaths"]["Disclaimer1"]}").first.value)
      output.disclaimer1 = OpFormat.parse_text(disclaimer[0]["body"])
      output.brand = "LEXUS"
      output.zip = @zipcode 
      lease_output_data << output
      end
      @parameters.each do |offer|
      output = OpFormat.new
      title1 = offer.xpath("#{@config["xpaths"]["title_1"]}").text().strip
      next if title1 != "Cash"
      output.title1 = title1
      output.offer_type = "Other"
      output.title2 = offer.xpath("#{@config["xpaths"]["title_2"]}").text().strip
      output.model_details = output.title2
      output.title3 = offer.xpath(".//h3").text().strip.gsub("\r\n"," ")
      offer_1_price = offer.xpath("#{@config["xpaths"]["offer_1"]}").text().strip
      output.cashback_amount = offer_1_price
      offer_1_months = offer.xpath("#{@config["xpaths"]["offer_1_months"]}").text().strip
      output.emi_months = offer_1_months
      output.offer1 = "#{offer_1_price}"+" for #{offer_1_months} months"
      output.offer2 = offer.xpath(".//p").text().strip.split("\r\n\r\n")[0]
      offer_enddate = offer.xpath(".//p[contains(@class,'terms')]").text.split("\r\n\r\n")[0].split(".")[0].strip.split(" ")[1]
      output.offer_end_date = "#{offer_enddate.split("/")[2]}/#{offer_enddate.split("/")[1]}/#{offer_enddate.split("/")[0]}"
      disclaimer = JSON.parse(offer.xpath("#{@config["xpaths"]["Disclaimer1"]}").first.value)
      output.disclaimer1 = OpFormat.parse_text(disclaimer[0]["body"])
      output.brand = "LEXUS"
      output.zip = @zipcode 
      lease_output_data << output
      end
    if(lease_output_data.size == 0)
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "LEXUS"
      output.offer_type = "Finance"
      @logger.info "No finance data found for #{@zipcode}" 
      lease_output_data << output 
    end
      return OpFormat.convert_to_json(lease_output_data,"finance_data")
  end
  
  def in_cookie
    "/tmp/cookie_#{@cookie_index}"  
  end

  def out_cookie
    @cookie_index += 1
    "/tmp/cookie_#{@cookie_index}"  
  end
  
  def get_standard_headers()
   @config["Headers"].join(" ")+ " -c #{out_cookie()}"
  end 
  
  def get_offer_page_headers()
    @config["Offer_Page_Headers"].join(" ").gsub("###Referrer###",@target_url)+ " -b #{in_cookie()} -c #{out_cookie()}"
  end
  
end