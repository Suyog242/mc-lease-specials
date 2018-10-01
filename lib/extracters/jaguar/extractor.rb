require_relative "../../../lib/extracters/base/base_extractor"
require_relative "../../../lib/utils/http_get"
require_relative "op_format.rb"
#require_relative "../../../lib/config/bmw.yml"
require "pry"
require "awesome_print"
require 'logging'
require 'logger'
require 'nokogiri'
require 'street_address'

class Extractor < BaseExtractor
  def initialize(make, zipcode)
    super(make, zipcode)
    @dealer_url = nil
    @http_get = HttpGet.new(%w[shader shader shader shader squid squid], nil, {shuffle_prefs: true}, @logger)
    @output_dir = "/tmp/cookie/#{@make}"
    @cookie_index =  1
    @dealer_urls = []
    @xpath = @config["xpaths"]
    @lease_listings, @finance_listings = [], []
  end
  
  def http_response(url, is_json, headers, tag)
    response = @http_get.get(url, {json_res: is_json, curl_opts: [headers, " -c #{out_cookie()}"],tag: tag})
    dom =  is_json ? response : Nokogiri::HTML(response)
    return dom
  end
  
  def load_target_page()
    creatae_ck_dir
    target_url = @config["target_page"].gsub(/###ZIPCODE###/, @zipcode)
    @logger.debug "Loading target page => #{target_url}"
    home_dom = http_response(target_url, false, @config["target_headers"].join(" "), "CURL- HOME_PAGE")
    dealer_info = home_dom.search(@xpath["dealer_info"])
    @logger.debug "Total Dealers available are => #{dealer_info.size}"
    dealer_info.each{|dealer|
      address = dealer.search(@xpath["address"])
      address_hash = StreetAddress::US.parse(address.text)
      if address_hash.postal_code == @zipcode
       @logger.debug "Dealer zipcode matches with requested zipcode => #{@zipcode}"
       dealer_url = dealer.search(@xpath["dealer_url"]).text
       @dealer_urls << dealer_url if dealer_url != ""
      end
    }
    if @dealer_urls.empty?
      @logger.debug "Dealer zipcode does not matches with requested zipcode taking first dealer."
     
      dealer_url = dealer_info[0].search(@xpath["dealer_url"]).text
      address = dealer_info[0].dealer_info[0].search(@xpath["address"]).text rescue ""
      address_hash = StreetAddress::US.parse(address)
      @dealer_zipcode = address_hash.postal_code rescue nil
      @dealer_urls << dealer_url if dealer_url != ""
    end
    load_retiler_page()
  end
  
  def load_retiler_page()
    model_urls = []
    @work_q = Queue.new
    @dealer_urls.each{|dealer_url|
      dealer_offer_url = "#{dealer_url}/special-offers.htm"
      dealer_offer_dom = http_response(dealer_offer_url, false, @config["dealer_offer_headers"].join(" "), "CURL- DEALER_OFFER")
      model_urls = dealer_offer_dom.search(@xpath["model_url_selector"])
      model_urls.each{|model_url| @work_q.push("#{dealer_url}#{model_url.text}")}
    } 
  end
  
  def set_zip_code()
    
  end
  
  def extract_lease_data
    extract_data("lease_data")
    if @lease_listings.flatten.empty?
      output = OpFormat.new
      output.zip = @zipcode
      output.offer_type = "Lease"
      output.brand = "JAGUAR"
      @lease_listings << output
    end
    OpFormat.convert_to_json(@lease_listings, "lease_data")
  end
  
  def extract_data(offer_type)
     parallel = @work_q.size > 1 ? 1 : @work_q.size - 1
    parallel = 1 if parallel < 1
      workers = (0...parallel).map do |thread_id|
        Thread.new do
          begin
            while model_offer_url = @work_q.pop(true)
              ap model_offer_url
              model_offer_dom = http_response(model_offer_url, false, @config["model_offer_header"].join(" "), "CURL- MODEL_OFFER")
              models_and_offers = model_offer_dom.search(@xpath["model_desc"])
              models_and_offers.each{|model_offer|
                output = OpFormat.new
                model_offer = model_offer.text
              if model_offer.include?('month lease') 
                output.zip = @zipcode
                output.offer_type = "Lease"
                output.dealer_zip = @dealer_zipcode
                output.brand = "JAGUAR"
                output.dealer_url = model_offer_url
                output.disclaimer1 = model_offer
                output.title1, output.emi_months, output.due_at_signing, downpayment, 
                security_deposit, output.acquisition_fee, output.mileage_charge, output.msrp = model_offer.gsub(",",'').
                                                                                               match(/.*?New(.*?with)\s+(\d+).*?\$(\d+).*?\$(\d+).*?\$(\d+).*? \$(\d+) acquisition.*(excess mileage.*?\/mile).*?(\d+)/)[1..8]
                                                                                              .map{|v| v.strip}  rescue nil
                                                                                
                output.tax_registration_exclusion = model_offer.include?("excludes retailer fees, taxes") ? "Y" : "N"
                output.down_payment =  downpayment  if !downpayment.nil?
                output.security_deposit = security_deposit if !security_deposit.nil?
                @lease_listings << output if !output.title1.nil?
              else
                output.zip = @zipcode
                output.dealer_zip = @dealer_zipcode
                output.brand = "JAGUAR"
                output.offer_type = "Finance"
                output.dealer_url = model_offer_url
                output.disclaimer1 = model_offer
                output.title1, output.emi, output.apr_rate,  output.emi_months =  model_offer.gsub(",",'')
                                                          .match(/.*?[n|N]ew(.*?[A-Z]{2}).*?can be as low as \$?(\d+[.]\d+) ?at (\d+[.]\d+)% for (\d+) months/)[1..4]
                                                          .map{|v| v.strip}  rescue nil
                output.tax_registration_exclusion = model_offer.include?("license and fees excluded") ? "Y" : "N"                                                           
                output.down_payment =  downpayment  if !downpayment.nil?
                output.security_deposit = security_deposit if !security_deposit.nil?
                @finance_listings << output if !output.title1.nil?
            end
              }   
            end
          rescue ThreadError
          end
        end
      end
      workers.map(&:join);
      
    clr_cookie
  end

  def extract_finance_data()
    if @finance_listings.flatten.empty?
      output = OpFormat.new
      output.zip = @zipcode
      output.offer_type = "Finance"
      output.brand = "JAGUAR"
      @finance_listings << output
    end
    OpFormat.convert_to_json(@finance_listings, "finance_data")
  end

  def in_cookie
    "#{@output_dir}/cookie_#{@cookie_index - 1}"  
  end

  def out_cookie
    "#{@output_dir}/cookie_#{@cookie_index}"  
    @cookie_index += 1
  end
  
  def creatae_ck_dir
    `mkdir -p '#{@output_dir}'`
  end
  
  def clr_cookie
    `rm -rf '#{@output_dir}'`
  end
end

 
=begin
Resolved and maintain Xtractly jiras Marcketcheck jira
OEM : Infinity
Lease : 



=end
 
