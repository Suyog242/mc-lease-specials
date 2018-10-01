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
    @http_get = HttpGet.new(%w[shader shader shader shader], nil, {shuffle_prefs: true}, @logger)
    `mkdir #{ENV['HOME']}/porschecookies`  
    @output_dir = "#{ENV['HOME']}/porschecookies"
    @cookie_index =  0
  end
  
  def load_target_page()
    #create_ck_dir
    @target_url = @config["target_page"].gsub("##ZIPCODE##",@zipcode)
    response = @http_get.get(@target_url, {json_res: false, curl_opts: [get_standard_headers]})
    @response_doc = Nokogiri::HTML(response)
    dealer_info = @response_doc.xpath("//div[contains(@class,'dealer-info')]//li[@class='blue_link']")[1]
    @dealer_url = dealer_info.xpath("./a/@href").text
#    ap @response
  end
  
  def set_zip_code()
    
  end
  
  def extract_data()
      lease_output_data = []
      dealer_response = @http_get.get(@dealer_url, {json_res: false, curl_opts: [get_dealer_headers]})
      dealer_doc = Nokogiri::HTML(dealer_response)
      
      dealer_offers_url = @dealer_url + "/specials/"
      @referer = @dealer_url
      offers_response = @http_get.get(dealer_offers_url, {json_res: false, curl_opts: [get_lease_headers]})
      offers_doc = Nokogiri::HTML(offers_response)
      
      offers_doc.xpath("//div[contains(@id,'specials-listing')]/div[@class='specials-listing-item']").each{|offers|
          begin
      next if !offers.xpath(".//p").text.include? "month lease"
      output = OpFormat.new
#      lease_url = offers.xpath("./a/@href").text
      lease_offer_url = @dealer_url + offers.xpath("./a/@href").text
      @referer = dealer_offers_url
      lease_response = @http_get.get(lease_offer_url, {json_res: false, curl_opts: [get_lease_headers]})
      lease_offer_doc = Nokogiri::HTML(lease_response)
      output.zip = @zipcode
      output.brand = "PORSCHE" 
      output.title1 = lease_offer_doc.xpath(".//div[@id='headline']/h1").text.strip
      output.offer1 = lease_offer_doc.xpath(".//div[@class='price']").text.strip + lease_offer_doc.xpath(".//div[@class='price-disclaimer']").text.strip
      output.emi = lease_offer_doc.xpath(".//div[@class='price']").text.strip.gsub(/\$/,'')
      output.disclaimer1 = lease_offer_doc.xpath(".//p[@dir='ltr'] | .//p/span[contains(@id,'docs')] | .//div[@class='price']/following-sibling::p").text.strip
      
      output.emi_months = output.disclaimer1.scan(/\d+ month lease/)[0].gsub(/ month lease/,'') rescue ""
      output.due_at_signing = output.disclaimer1.scan(/\$\d+.\d+ total due at signing/)[0].gsub(/ total due at signing|\$|,/,'')
      output.offer_end_date = output.disclaimer1.scan(/Offer ends \d+.\d+.\d+/)[0].gsub(/Offer ends /,'') rescue nil
      output.offer_end_date = output.disclaimer1.scan(/Offer ends\d+.\d+.\d+/)[0].gsub(/Offer ends/,'') if output.offer_end_date.eql? nil 
      lease_output_data << output
          rescue Exception => e
        @logger.debug "Error to grab listings- #{e.message} - #{e.backtrace.join("\n")}"
        @logger.error "Error in  Fetching data for zipcode = #{@zipcode}"
      end
      }
       clr_cookie
       OpFormat.convert_to_json(lease_output_data) 
  end
  
  def get_standard_headers
    @config["locaion_headers"].join(" ").gsub("##ZIPCODE##",@zipcode) + " -b #{in_cookie()} -c #{out_cookie()}"
  end
  
  def get_dealer_headers
    @config["dealer_headers"].join(" ").gsub("##ZIPCODE##",@zipcode) + " -b #{in_cookie()} -c #{out_cookie()}"
  end
  
  def get_lease_headers
    @config["lease_headers"].join(" ").gsub(/##REFERER##/, @referer) + " -b #{in_cookie()} -c #{out_cookie()}"
  end
  
  def in_cookie
    "#{@output_dir}/cookie_#{@cookie_index}"  
  end

  def out_cookie
    @cookie_index += 1
    "#{@output_dir}/cookie_#{@cookie_index}"  
  end
  
#  def create_ck_dir
#    `mkdir -p '#{@output_dir}'`
#  end
  
  def clr_cookie
    `rm -rf '#{@output_dir}'`
  end
  
end