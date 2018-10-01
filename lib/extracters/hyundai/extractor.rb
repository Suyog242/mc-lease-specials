require_relative "../../../lib/extracters/base/base_extractor"
require_relative "../../../lib/utils/http_get"
require_relative "op_format.rb"
#require_relative "../../../lib/config/bmw.yml"
require "pry"
require "awesome_print"
require 'logging'
require 'logger'
require 'nokogiri'

class Extractor < BaseExtractor
  def initialize(make, zipcode)
    super(make, zipcode)
    @http_get = HttpGet.new(%w[squid squid shader shader shader shader ], nil, {shuffle_prefs: true}, @logger)
    @output_dir = "/tmp/cookie/#{@make}/#{@zipcode}"
    @cookie_index =  1
    @lease_listings= []
    @xpath= @config["xpaths"]
  end
  
  def load_target_page()
    creatae_ck_dir
    params = ["__CSRFTOKEN", "__EVENTARGUMENT", "__VIEWSTATE"]
    home_page_response = @http_get.get(@config["target_page"], {json_res: false, curl_opts: [@config["target_headers"].join(" "), " -c #{out_cookie()}"],tag: "CURL- Target"})
    home_dom = Nokogiri::HTML(home_page_response)
    post = post_data
    params.each{|param|
      post[param] = home_dom.search("//input[@id='#{param}']/@value").to_s rescue nil
    }
    @post_str = post.map{|k,v| v.nil? ? "#{k}=#{v}" : "#{k}=#{CGI::escape(v)}" }.join("&")
       
  end
  
  def set_zip_code()
    headers= @config["post_headers"].join(" ").gsub(/###POST_DATA###/,@post_str)
    inv_page_resp = @http_get.get(@config["target_page"], {json_res: false, curl_opts: [headers, " -b #{in_cookie()}"],tag: "CURL- POST"})
    @inv__dom = Nokogiri::HTML(inv_page_resp)
  end
  
  def extract_lease_data()
    lease_output_data = []
    lease_offers = @inv__dom.search(@xpath["p_xpath"])
    lease_offers.each{|lease_offer|
      output = OpFormat.new
      if !lease_offer.search(@xpath["desclaimer"]).empty?
        output.zip = @zipcode
        output.brand = "HYUNDAI"
        output.offer_type = "Lease"
        output.disclaimer1 = lease_offer.search(@xpath["desclaimer"]).text.gsub(/\n\s+/,"") rescue nil
        output.title1, output.title2 = lease_offer.search(@xpath["title"]).text.split("-", 2) rescue nil
        lease_offer.search(@xpath["offer"]).each{|_offer| output.offer1 = _offer.text.gsub(/\r\n\s+/,"") if _offer.text.include?("Lease starting")}
        output.emi, output.emi_months = output.offer1.gsub(",","")
        .match(/.*\$(\d+)\/month.*for\s+(\d+)\s+months/)[1..2]
        .map{|v| "#{v}"} rescue nil
        offer_start_date, offer_end_date = output.offer1.gsub(",","")
        .match(/\((\d+.\d+.\d+)\s-\s(\d+.\d+.\d+)\)/)[1..2]
        .map{|v| "#{v}"} rescue nil                                     
        output.due_at_signing, output.msrp, output.acquisition_fee, output.mileage_charge, output.disposition_fee = 
        output.disclaimer1.gsub(",","").match(/\$(\d+) due at lease signing.*MSRP \$(\d+).*\$(\d+) acquisition.*\$([^\d+].\d+.*?\/year).*?\$(\d+) disposition fee/)[1..5].map{|v| v.strip}  rescue nil
       output.offer_start_date = Date.strptime(offer_end_date, '%m/%d/%y').to_s if !offer_start_date.nil?
       output.offer_end_date = Date.strptime(offer_end_date, '%m/%d/%y').to_s  if !offer_end_date.nil?
        output.tax_registration_exclusion = output.disclaimer1.include?("Excludes registration, tax, title and license") ? "Y" : "N"
        
        lease_output_data << output
      end
    }
#    clr_cookie
    if lease_output_data.flatten.empty?
      output = OpFormat.new
      output.zip = @zipcode
      output.offer_type = "Lease"
      output.brand = "HYUNDAI"
      lease_output_data << output
    end
    @logger.info "Total #{lease_output_data.size} records found for #{@zipcode}"
   OpFormat.convert_to_json(lease_output_data, "lease_data") #Converting array of output objects in to json format
  end
  
  
  def extract_finance_data()
    finance_output_data = []
    lease_offers = @inv__dom.search(@xpath["p_xpath"])
    lease_offers.each{|lease_offer|
      output = OpFormat.new
      get_data(lease_offer, output)
      
      apr_months_arr = output.disclaimer1.scan(/(\d+\.\d+)\% Annual Percentage.*?(\d+) months|Special Low (\d+[.]\d+).*?(\d+) months/) rescue []
      apr_months_arr.each{|apr_month|
        output = OpFormat.new
        get_data(lease_offer, output)
        if !apr_month[0].nil? && !apr_month[1].nil?
          output.apr_rate = "#{apr_month[0]}%"
          output.emi_months = apr_month[1]
        else
          output.apr_rate = "#{apr_month[2]}%"
          output.emi_months = apr_month[3]
        end
        finance_output_data << output
      }
      finance_output_data << output
    }
    clr_cookie
    if finance_output_data.flatten.empty?
      output = OpFormat.new
      output.zip = @zipcode
      output.brand = "HYUNDAI"
      output.offer_type = "Finance"
      finance_output_data << output
    end
    @logger.info "Total #{finance_output_data.flatten.size} records found for #{@zipcode}"
    OpFormat.convert_to_json(finance_output_data.flatten, "finance_data") #Converting array of output objects in to json format
  end
  
  def get_data(lease_offer, output)
    if !lease_offer.search(@xpath["finance"]).empty?
       
      offer = nil
      output.zip = @zipcode
      output.brand = "HYUNDAI"
      output.offer_type = "Finance"
        output.disclaimer1 = lease_offer.search(@xpath["finance"]).text.gsub(/\n\s+/,"") rescue nil
        output.title1, output.title2 = lease_offer.search(@xpath["title"]).text.split("-", 2) rescue nil
        lease_offer.search(@xpath["offer"]).each{|_offer| output.offer1 = _offer.text.gsub(/\r\n\s+/,"") if _offer.text.include?("Low APR")}
        output.apr_rate, output.emi_months = output.offer1.gsub(",","")
        .match(/.*(^\d+[.]\d+)% financing.*up to\s+(\d+)\s+months/)[1..2]
        .map{|v| "#{v}"} rescue nil
        offer_start_date, offer_end_date = output.offer1.gsub(",","")
        .match(/\((\d+.\d+.\d+)\s-\s(\d+.\d+.\d+)\)/)[1..2]
        .map{|v| "#{v}"} rescue nil
        
        output.offer_start_date = Date.strptime(offer_end_date, '%m/%d/%y').to_s  rescue nil if !offer_start_date.nil?
        output.offer_end_date = Date.strptime(offer_end_date, '%m/%d/%y').to_s  rescue nil if !offer_end_date.nil?
#        output.offer_end_date = lease_offer.search(".//ul[@class='promo_features']/span").text.split("-",2).gsub(")","")   rescue ""
#        output.down_payment = output.offer1.gsub(",","").match(/months with\s+\$(\d+)/)[1] rescue nil
      end
      
      if !lease_offer.search(@xpath["cash"]).empty?
      offer = nil
      output.zip = @zipcode
      output.brand = "HYUNDAI"
      output.offer_type = "Other"
        output.disclaimer1 = lease_offer.search(@xpath["cash"]).text.gsub(/\n\s+/,"") rescue nil
        output.cashback_amount = output.disclaimer1.gsub(",","").match(/\$(\d+)\s+.*Bonus\s+Cash/)[1] rescue nil
        output.title1, output.title2 = lease_offer.search(@xpath["title"]).text.split("-", 2) rescue nil
        lease_offer.search(@xpath["offer"]).each{|_offer| output.offer1 = _offer.text.gsub(/\r\n\s+/,"") if _offer.text.include?("Retail Bonus Cash")}
        offer_start_date = lease_offer.search(".//ul[@class='promo_features']/span").text.split("-",1).gsub("(","")   rescue nil
        offer_end_date = lease_offer.search(".//ul[@class='promo_features']/span").text.split("-",2).gsub(")","")   rescue nil
        amount = output.offer1.gsub(",","").match(/^(\$\d+)\s/)[1] rescue nil
        output.offer_start_date, output.offer_end_date = output.offer1.gsub(",","")
        .match(/\((\d+.\d+.\d+)\s-\s(\d+.\d+.\d+)\)/)[1..2]
        .map{|v| "#{v}"} rescue nil
        
        output.offer_start_date =  Date.strptime(offer_end_date, '%m/%d/%y').to_s rescue nil if !offer_start_date.nil?
       output.offer_end_date =  Date.strptime(offer_end_date, '%m/%d/%y').to_s  rescue nil if !offer_end_date.nil?
#        output.down_payment = output.offer1.gsub(",","").match(/months with\s+\$(\d+)/)[1] rescue nil
      end
  end
  
  
  
  def post_data
    post_data = {
      "__EVENTTARGET" => "ctl00$ContentPlaceHolderContent$specialOffersResults$lnkBtnFind",
      "ctl00$ContentPlaceHolderContent$specialOffersResults$ddlVehicle" => "ALL",
      "ctl00$ContentPlaceHolderContent$specialOffersResults$txtZipCode" => @zipcode,
      "ctl00$ContentPlaceHolderContent$specialOffersResults$hidModel" => "ALL",
      "ctl00$ContentPlaceHolderContent$specialOffersResults$hdnPostCode" => "1",
      "txtFirstName" => nil,
      "txtLastName" => nil,
      "txtEmailAddress" => nil,
      "txtZipCode" => nil,
      "fancySelect" => nil
    }
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

 