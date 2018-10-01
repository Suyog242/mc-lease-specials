require_relative "../../../lib/extracters/base/base_extractor"
require_relative "../../../lib/utils/http_get"
require_relative "op_format.rb"
require 'uri'
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
        dealer_urls = dealer.search(@xpath["dealer_url"]).map{|url| url.text}
        dealer_urls.uniq.each{|dealer_url| @dealer_urls << dealer_url if dealer_url != ""}
      end
    }
    if @dealer_urls.empty?
      @logger.debug "Dealer zipcode does not matches with requested zipcode taking first dealer."
      dealer_urls = dealer_info[0].search(@xpath["dealer_url"]).map{|url| url.text}
      dealer_urls.uniq.each{|dealer_url| @dealer_urls << dealer_url if dealer_url != ""}
      address = dealer_info[0].search(@xpath["address"])
      address_hash = StreetAddress::US.parse(address.text)
      @dealer_zipcode = address_hash.postal_code rescue nil
    end
    load_retiler_page()
  end
  
  def load_retiler_page()
    model_urls = []
    @work_q = Queue.new
    @dealer_urls.each{|dealer_url|
      dealer_home_page_dom = http_response(dealer_url, false, @config["dealer_home_page_headers"].join(" "), "CURL- dealer_home_page")
      current_offer = dealer_home_page_dom.search("//ul[@class=' dropdown-menu']//a[@title='Current Offers']/@href")[0].text rescue nil
      special_offer = dealer_home_page_dom.search("//i/following-sibling::text()[contains(.,'View Land Rover Offers') or contains(.,'Special Offers')]/..").first["href"] rescue nil
      special_offer = "/specials/new.htm" if special_offer.nil?
      special_offer_url = "#{dealer_url}#{special_offer}"
      @special_offer_url  = special_offer_url
      zipcode = nil
      @work_q.push([special_offer_url, current_offer])
    } 
    
  end
  
  def set_zip_code()
     extract_data()
  end
  
  def extract_data()
    parallel = @work_q.size > 1 ? 1 : @work_q.size - 1
    parallel = 1 if parallel < 1
    workers = (0...parallel).map do |thread_id|
      Thread.new do
        begin
          while  offer_urls  = @work_q.pop(true)
            special_offer_url , current_offer_url = offer_urls
            extract_lease(special_offer_url , current_offer_url)
          end
        rescue ThreadError
        end
      end
    end
    workers.map(&:join);
    
    clr_cookie
                
  end
  
  def extract_lease_data
   if @lease_listings.flatten.empty?
      output = OpFormat.new
      output.zip = @zipcode
      output.offer_type = "Lease"
      output.brand = "LANDROVER"
      @lease_listings << output
    end
    
    OpFormat.convert_to_json(@lease_listings.flatten, "lease_data")
  end
  
  def extract_lease(special_offer_url , current_offer_url)
    extract_special_offers(special_offer_url, "Lease") if !special_offer_url.nil? && special_offer_url != ""  
    extract_current_offers(current_offer_url) if !current_offer_url.nil? && current_offer_url != "" 
  end
  
  def extract_special_offers(special_offer_url, type)
    @lease_listings, @finance_listings = [], []
    dealer_offer_dom = http_response(special_offer_url, false, @config["dealer_offer_headers"].join(" "), "CURL- MODEL_OFFER")
    models_and_offers = dealer_offer_dom.search(@xpath["model_desc"])
    models_and_offers.each{|model_offer|
      output = OpFormat.new
      model_offer = model_offer.text
      if model_offer.include?('month lease') 
        output.offer_type = "Lease"
        output.zip = @zipcode
        output.dealer_zip = @dealer_zipcode
        output.brand = "LANDROVER"
        output.dealer_url = special_offer_url
        output.disclaimer1 = model_offer
        output.title1, output.emi_months, output.due_at_signing, downpayment, 
        security_deposit, output.acquisition_fee, output.mileage_charge, output.msrp = model_offer.gsub(",",'').match(/.*?New(.*?with)\s+(\d+).*?\$(\d+).*?\$(\d+).*?\$(\d+).*? \$(\d+) acquisition.*(excess mileage.*?\/mile).*?(\d+)/)[1..8].map{|v| v.strip} rescue nil
        output.tax_registration_exclusion = model_offer.include?("excludes retailer fees, taxes") ? "Y" : "N"
        output.offer1 = model_offer.gsub(",",'').match(/\$\d+ due at signing/)[0].upcase
        offer_end_date = model_offer.match(/delivery from retailer stock by .*(\d+\/\d+\/\d+)\./)[1] rescue nil
        output.offer_end_date = Date.strptime(offer_end_date, '%m/%d/%y').to_s rescue nil if !offer_end_date.nil?
        output.down_payment =  "#{downpayment}"  if !downpayment.nil?
        output.security_deposit = "#{security_deposit}" if !security_deposit.nil?
        output.title1.gsub!("with")
        @lease_listings << output
      else
        output.zip = @zipcode
        output.offer_type = "Finance"
        output.dealer_zip = @dealer_zipcode
        output.brand = "LANDROVER"
        output.dealer_url = special_offer_url
        output.disclaimer1 = model_offer
        output.title1, output.emi, output.apr_rate,  output.emi_months = model_offer.gsub(",",'')
        .match(/.*?[n|N]ew(.*?[A-Z]{2}).*?can be as low as \$?(\d+[.]\d+) ?at (\d+[.]\d+)% for (\d+) months/)[1..4].map{|v| v.strip}  rescue nil
        output.tax_registration_exclusion = model_offer.include?("license and fees excluded") ? "Y" : "N"  
        output.down_payment =  "#{downpayment}"  if !downpayment.nil?
        output.security_deposit = "#{security_deposit}" if !security_deposit.nil?
        ap output
        @finance_listings << output
      end
    }
    
  end
  
  def extract_current_offers(current_offer_url)
    url = "https://incentive.dealerinspire.com/national-offer?&zipcode=#{@zipcode}&provider=LandRoverNationalProvider"
    headers = @config["current_offer_headers"].join(" ").gsub("###REFERER###",current_offer_url)
    curr_off_json = http_response(url, true, headers , "CURL- CURRENT_OFFER")
    _offers = curr_off_json["_embedded"]["national_offer"] 
    _offers.each{|curr_off|
      output = OpFormat.new
      if curr_off["offer_type"] == "Lease"
        desc = curr_off["full_description"]
        output.dealer_url = current_offer_url
        output.zip = @zipcode
        output.dealer_zip = @dealer_zipcode
        output.brand = "LANDROVER"
        output.msrp = "#{curr_off["msrp"]}"
        output.emi = "#{curr_off["monthly_payment"]}"
        output.emi_months = curr_off["term_max"]
        
        output.down_payment = "#{desc.gsub(",","").match(/(\d+)\s+Down payment/)[1]}" rescue nil
        output.acquisition_fee = "#{desc.gsub(",","").match(/(\d+)\s+Acquisition/)[1]}" rescue nil
        output.security_deposit = "#{desc.gsub(",","").match(/(\d+)\s+Security/)[1]}" rescue nil
        output.due_at_signing = "#{desc.gsub(",","").match(/(\d+)\s+due at signing/)[1]}" rescue nil
        output.dealer_contribution = curr_off["suggested_dealer_contrib"]
        
        output.title1 = curr_off["name"]
        output.offer1 = "#{output.emi}Per month for #{output.emi_months} months"
        output.offer2 = curr_off["short_description"]
        
        output.disclaimer1 = desc
        
        @lease_listings << output
      end
    }
    
  end
  
  def extract_finance_data
   if @finance_listings.flatten.empty?
      output = OpFormat.new
      output.zip = @zipcode
      output.offer_type = "Finance"
      output.brand = "LANDROVER"
      @finance_listings << output
    end
    
    OpFormat.convert_to_json(@finance_listings.flatten, "finance_data")
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






