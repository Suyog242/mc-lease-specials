require 'nokogiri'
require 'ap'
require 'date'
require_relative "../../../lib/extracters/base/base_extractor"
require_relative "../../../lib/utils/http_get.rb"
require_relative "op_format.rb"

class Extractor < BaseExtractor
  def initialize(make, zipcode)
    super(make, zipcode)
    @http_get = HttpGet.new(%w[shader shader shader], nil, {shuffle_prefs: true}, @logger)
    @cookie_index = 0
  end
  
  def load_target_page()
    @offers_url = []
    @target_url = @config["target_page"].gsub("###zipcode###",@zipcode.to_s)
    @logger.info "Loading page #{@target_url}"
    response = Nokogiri::HTML(@http_get.get(@target_url, {json_res: false, curl_opts: [get_headers("standard")]}).to_json)
    return if !response.xpath("//div[contains(@class,'no-results-wrapper')]").text.empty?
    dealer_url = response.xpath("//div[contains(@class,'Teaser-services')]//a[contains(@class,'Teaser-servicesLink')]")[2]["href"].gsub(/[\\\\\"]/,"")
    referer = dealer_url.scan(/www.*com/).join("")
    dealer_response = Nokogiri::HTML(@http_get.get(dealer_url, {json_res: false, curl_opts: [get_headers("dealer").gsub(/#referer#/,referer)]}).to_json)
    dealer_response.xpath("//noscript//a").each do |_offers|
      @offers_url << "#{dealer_url.gsub(/https?/,"https").gsub(/com(.*)/,"")}com#{_offers.attributes["href"].value.gsub(/[\\\\\"]/,"")}"
    end
  end
  
  def set_zip_code()
    
  end
  
  def fields_data(_offer , output)
    output.title3 = _offer.xpath(".//h4[contains(@class,'incentive-type-heading')]").text.strip rescue nil
    output.offer1 = _offer.xpath(".//hgroup/h3").text.strip rescue nil
    output.offer2 = _offer.xpath(".//ul[contains(@class,'clearfix ddc-span12')]/li")[0].text.strip rescue nil
    output.offer3 = _offer.xpath(".//ul[contains(@class,'clearfix ddc-span12')]/li")[1].text.strip rescue nil
    output.offer4 = _offer.xpath(".//span[contains(@class,'valid-date')]/time").text.strip.gsub(/\\n/,"") rescue nil
    output.offer5 = _offer.xpath(".//p[contains(@class,'offer-details')]/em").text.strip rescue nil
    output.disclaimer1 = _offer.xpath(".//dd[contains(@class,'incentive-disclaimers')]//p").text.strip rescue nil
    return output
  end
  
  def extract_lease_data()
    lease_output_data = []
    if (@offers_url.empty?)
      output = OpFormat.new 
      output.zip,output.brand,output.offer_type = @zipcode,"VOLVO","Lease"
      @logger.info "No lease data found for #{@zipcode}" 
      lease_output_data << output 
      return OpFormat.convert_to_json(lease_output_data, "lease_data")
    end
    
    work_q = Queue.new
    @offers_url.each do |_url|
      work_q.push _url
    end
    @logger.info "Total urls queued for #{@zipcode} - #{work_q.size}"
    thread_index = 0
    parallel = work_q.size > 3 ? 3 : work_q.size-1 #max 3 threads
    parallel = 1 if parallel < 1
    @finance_output_data = []
    workers = (0...parallel).map do |thread_id|
      Thread.new do
        begin
          while _offer_url = work_q.pop(true)
            thread_index += 1
            referer = _offer_url.scan(/www.*com/).join("")
            offer_response = Nokogiri::HTML(@http_get.get(_offer_url, {json_res: false, curl_opts: [get_headers("offer").gsub(/#referer#/,referer)]}).to_json)
            dealer_name = offer_response.xpath("//span[contains(@class,'org')]").text.strip rescue nil
            @logger.info "No lease offers for #{_offer_url}" if offer_response.xpath("//div[contains(@class,'type-1')]//li")[1].nil?
            offer_response.xpath("//section[contains(@data-offer,'LEASE')]/article").each do |_offer|
              output = OpFormat.new
              output.zip,output.brand,output.offer_type = @zipcode,"VOLVO","Lease"
              output.dealer_name,output.dealer_url = dealer_name,_offer_url
              output.model_details = offer_response.xpath("//div[contains(@class,'trim-overview')]/div/p").text rescue nil
              output.emi = _offer.xpath(".//hgroup/h3").text.strip.scan(/\d+/)[0].to_s rescue nil
              output.emi_months = _offer.xpath(".//hgroup/h3").text.strip.scan(/\d+/)[1].to_s rescue nil
              output.due_at_signing = _offer.xpath(".//ul[contains(@class,'clearfix ddc-span12')]/li")[1].text.gsub(/\D+/,"").to_s rescue nil
              output.offer_start_date = Date.strptime("#{_offer.xpath(".//span[contains(@class,'valid-date')]/time").text.scan(/\d+\/\d+\/\d+/)[0]}", "%d/%m/%Y").to_s rescue nil
              output.offer_end_date = Date.strptime("#{_offer.xpath(".//span[contains(@class,'valid-date')]/time").text.scan(/\d+\/\d+\/\d+/)[1]}", "%d/%m/%Y").to_s rescue nil
              output.title1 = offer_response.xpath("//header[contains(@class,'incentives-header')]").text.gsub(/\\n/,"") rescue nil
              output.title2 = "Lease Offers"
              output.msrp = _offer.xpath(".//dd[contains(@class,'incentive-disclaimers')]//p").text.scan(/\d+,\d+ MSRP/)[0].split(" ")[0].to_s rescue nil
              output.mileage_charge = _offer.xpath(".//dd[contains(@class,'incentive-disclaimers')]//p").text.scan(/Lessee is.*/)[0] rescue nil
              output = fields_data(_offer , output)
              output.disclaimer2 = _offer.xpath(".//dd[contains(@class,'incentive-disclaimers')]//li//following-sibling::text()").text.strip rescue nil
              output.tax_registration_exclusion = (output.disclaimer2.include?"excludes taxes")? "Y":nil rescue nil 
              output.security_deposit = 0.to_s if output.disclaimer1.include?"No security deposit"
              lease_output_data << output    
            end
            
            offer_response.xpath("//section[contains(@data-offer,'CASH')]/article").each do |_offer|
              output = OpFormat.new
              output.zip,output.brand,output.offer_type = @zipcode,"VOLVO","Other"
              output.cashback_amount = _offer.xpath(".//hgroup/h3").text.scan(/\d+,\d+/)[0].to_s rescue nil
              output.dealer_name,output.dealer_url = dealer_name,_offer_url
              output.model_details = offer_response.xpath("//div[contains(@class,'trim-overview')]/div/p").text rescue nil
              output.offer_start_date = Date.strptime("#{_offer.xpath(".//span[contains(@class,'valid-date')]/time").text.scan(/\d+\/\d+\/\d+/)[0]}", "%d/%m/%Y").to_s rescue nil
              output.offer_end_date = Date.strptime("#{_offer.xpath(".//span[contains(@class,'valid-date')]/time").text.scan(/\d+\/\d+\/\d+/)[1]}", "%d/%m/%Y").to_s rescue nil
              output.title1 = offer_response.xpath("//header[contains(@class,'incentives-header')]").text.gsub(/\\n/,"") rescue nil
              output.title2 = "Cash Offers"
              output = fields_data(_offer , output)
              output.disclaimer2 = _offer.xpath(".//dd[contains(@class,'incentive-disclaimers')]//li").text.strip rescue nil
              output.security_deposit = 0.to_s if output.disclaimer1.include?"No security deposit"
              @finance_output_data << output    
            end
          end
        rescue ThreadError
          @logger.error "DThread #{thread_id} - No jobs in queue to process"
        end
      end
    end
    workers.map(&:join);
    
    @logger.info "Total #{lease_output_data.size} records found for #{@zipcode}" 
    return OpFormat.convert_to_json(lease_output_data, "lease_data") 
  end
  
  def extract_finance_data()
    finance_output_data = []
    if (@offers_url.empty?)
      output = OpFormat.new 
      output.zip,output.brand,output.offer_type = @zipcode,"VOLVO","Other"
      @logger.info "No finance data found for #{@zipcode}" 
      finance_output_data << output 
      return OpFormat.convert_to_json(finance_output_data, "finance_data")
    end
    @logger.info "Total #{@finance_output_data.size} records found for #{@zipcode}" 
    return OpFormat.convert_to_json(@finance_output_data, "finance_data") 
  end
  
  def get_headers(type)
    @config["#{type}_headers"].join(" ") 
  end 
end



