require 'nokogiri'
require 'ap'
require 'net/http'
require 'uri'
require 'open-uri'
require 'yaml'
require 'date'
require 'time'
require "selenium"
require "selenium-webdriver"
require "selenium-proxy"
require_relative "../../../lib/extracters/base/base_extractor"
require_relative "../../../lib/utils/http_get.rb"
require_relative "op_format.rb"

class Extractor < BaseExtractor
  def initialize(make, zipcode)
    super(make, zipcode)
    basic_proxies = YAML.load_file("./lib/utils/proxies.yml")
    @proxy = basic_proxies["squid"].sample
  end
  
  def load_target_page()
    sleep(rand(20))
    @response = nil
    @target_url = @config["target_page"].gsub("###zipcode###",@zipcode.to_s)
    @logger.info "Loading page #{@target_url}"
    #wait = Selenium::WebDriver::Wait.new(timeout: 5)
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument('--headless')
    options.add_argument('--ignore-certificate-errors')
    options.add_argument('--proxy-server=###PROXY###'.gsub(/###PROXY###/,@proxy))
    driver = Selenium::WebDriver.for :chrome, options: options
    driver.navigate.to "#{@target_url}"
    #wait.until { driver.find_elements(:class,'js-locationInput').first.displayed? }
    driver.find_elements(:class,'js-locationInput').first.send_keys "#{@zipcode.to_s}"
    driver.find_elements(:class,'js-submitLocationChange').first.click
    @response = Nokogiri::HTML(driver.page_source) rescue nil
    scraped_zipcode = @response.xpath("//a[@class='zipCode js-locationChange']")[0].text rescue nil
    @response = scraped_zipcode==@zipcode? @response : nil
  end
  
  def set_zip_code()
    
  end
  
  def lease_data(_offer)
    output = OpFormat.new     
    output.zip,output.brand,output.offer_type = @zipcode,"VOLKSWAGEN","Lease"     
    output.emi = _offer.xpath(".//h2[@class='offerTitle']").text.strip.scan(/\d+/)[0] rescue nil
    output.emi_months = _offer.xpath(".//h2[@class='offerTitle']").text.strip.scan(/\d+/)[1] rescue nil
    output.due_at_signing = _offer.xpath(".//p[@class='offerSubtitle']").text.gsub(/\D+/,"") rescue nil
    output.offer_end_date =  DateTime.parse(_offer.xpath(".//span[@class='offerEndDate']").text.strip).to_s.split("T").first rescue nil
    output.security_deposit = _offer.xpath(".//p[@class='offerSubtitle']").text.gsub(/.*signing\.\s/,'') rescue nil
    output.msrp = _offer.xpath(".//p[@class='offerLegal']").text.scan(/MSRP\sof\s\$\d+\,\d+/)[0].gsub(/\D+/,'').to_s rescue nil
    output.disposition_fee = _offer.xpath(".//p[@class='offerLegal']").text.scan(/disposition fee of\s\$\d+/)[0].gsub(/\D+/,'') rescue nil
    output.acquisition_fee = _offer.xpath(".//p[@class='offerLegal']").text.scan(/acquisition fee of\s\$\d+/)[0].gsub(/\D+/,'') rescue nil
    output.mileage_charge = _offer.xpath(".//p[@class='offerLegal']").text.scan(/\$\d+.\d+\/mile.*and\suse/)[0] rescue nil
    output.title1 = _offer.xpath(".//p[contains(@class,'offerType-lease')]").text.strip rescue nil
    output.title2 = "LEASE" rescue nil
    output.offer1 = _offer.xpath(".//h2[@class='offerTitle']").text.strip rescue nil
    output.offer2 = _offer.xpath(".//p[@class='offerSubtitle']").text.strip rescue nil
    output.offer3 = _offer.xpath(".//p[@class='offerExclusions']").text.strip rescue nil
    output.offer4 = _offer.xpath(".//p[@class='offerCopy']").text.strip rescue nil
    output.disclaimer1 = OpFormat.parse_text(_offer.xpath(".//p[@class='offerLegal']").text.strip) rescue nil  
    output.tax_registration_exclusion = (_offer.xpath(".//p[@class='offerCopy']").text.include?"Excludes tax")? "Y":nil rescue nil 
    return output
  end
  
  def apr_data(_offer)
    output = OpFormat.new  
    output.zip,output.brand,output.offer_type = @zipcode,"VOLKSWAGEN","Finance"
    output.apr_rate = _offer.xpath(".//h2[@class='offerTitle']")[0].children[0].text.split('%')[0] rescue nil
    output.emi_months = _offer.xpath(".//h2[@class='offerTitle']").text.scan(/\d{2}/)[0] rescue nil
    output.title1 = _offer.xpath(".//p[contains(@class,'offerType-apr')]").text.strip rescue nil
    output.title2 = "APR" rescue nil
    output = finance_fields_data(_offer, output)
    return output
  end
  
  def other_data(_offer)
    output = OpFormat.new  
    output.zip,output.brand,output.offer_type = @zipcode,"VOLKSWAGEN","Other"
    output.cashback_amount = _offer.xpath(".//p[@class='offerCopy']").text.strip.scan(/\d+/)[0] rescue nil
    output.title1 = _offer.xpath(".//p[contains(@class,'offerType-other')]").text.strip rescue nil 
    output.title2 = "OTHER" rescue nil
    output = finance_fields_data(_offer, output)
    output.offer_start_date = DateTime.parse(output.disclaimer1.match(/from(.*?)to/)[1].strip).to_s.split("T").first rescue nil
    return output
  end
  
  def finance_fields_data(_offer, output)
    output.offer_end_date = DateTime.parse(_offer.xpath(".//span[@class='offerEndDate']").text.strip).to_s.split("T").first rescue nil
    output.offer1 = _offer.xpath(".//h2[@class='offerTitle']").text.strip rescue nil
    output.offer2 = _offer.xpath(".//p[@class='offerSubtitle']").text.strip rescue nil
    output.offer3 = _offer.xpath(".//p[@class='offerAdditionalTerms']").text.strip rescue nil 
    output.offer3 = _offer.xpath(".//p[@class='offerExclusions']").text.strip rescue nil if (output.offer3.nil? || output.offer3.empty?)
    output.offer4 = _offer.xpath(".//p[@class='offerCopy']").text.strip rescue nil
    output.disclaimer1 = OpFormat.parse_text(_offer.xpath(".//p[@class='offerLegal']").text.strip) rescue nil
    return output
  end
  
  def extract_lease_data()
    lease_output_data = []
    if(@response.nil?)
      output = OpFormat.new  
      output.zip,output.brand,output.offer_type = @zipcode,"VOLKSWAGEN","Lease"
      @logger.info "No lease data found for #{@zipcode}" 
      lease_output_data << output 
      return OpFormat.convert_to_json(lease_output_data)
    end
    @response.xpath("//div[@data-type='LEASE']").each { |_offer| lease_output_data << lease_data(_offer)  }
    @logger.info "Total #{lease_output_data.size} records found for #{@zipcode}" 
    return OpFormat.convert_to_json(lease_output_data, "lease_data") 
  end
  
  def extract_finance_data()
    finance_output_data = []
    if(@response.nil?)
      output = OpFormat.new  
      output.zip,output.brand,output.offer_type = @zipcode,"VOLKSWAGEN","Finance" 
      @logger.info "No finance data found for #{@zipcode}" 
      finance_output_data << output 
      return OpFormat.convert_to_json(finance_output_data, "finance_data")
    end
    @response.xpath("//div[@data-type='APR']").each { |_offer| finance_output_data << apr_data(_offer)  }
    @response.xpath("//div[@data-type='OTHER']").each { |_offer| finance_output_data << other_data(_offer) }
    @logger.info "Total #{finance_output_data.size} APR and Other records found for #{@zipcode}" 
    return OpFormat.convert_to_json(finance_output_data, "finance_data") 
  end
  
  def get_standard_headers
    @config["headers"].join(" ")
  end 
end
