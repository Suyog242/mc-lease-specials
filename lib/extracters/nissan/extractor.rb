require_relative "../../../lib/extracters/base/base_extractor"
require_relative "../../../lib/utils/http_get"
require "pry"
require 'uuidtools'
require "awesome_print"
require 'logging'
require 'logger'
require 'nokogiri'
require_relative "op_format.rb"

class Extractor < BaseExtractor
  attr_accessor :uniq_id
  
  def initialize(make, zip)
    super(make, zip)
    @output_dir = "/tmp/nissancookies"
    @uniq_id = UUIDTools::UUID.random_create.to_s.split("-")[0]
    `mkdir -p "#{@output_dir}/#{@uniq_id}"` 
    @http_get = HttpGet.new(%w[shader shader shader], nil, {shuffle_prefs: true}, @logger)
    @cookie_index =  0
  end
  
  def load_target_page()
    #create_ck_dir
    @target_url = @config["target_page"].gsub("###zipcode###", @zipcode) 
    @loc_availability = @http_get.get(@target_url, {json_res: false, curl_opts: [get_standard_headers]})
    if @http_get.last_curl_status != "200"
      retry_count = 2 
      while retry_count > 0 
        http_get = HttpGet.new(%w[none none none], nil, {shuffle_prefs: true}, @logger)
        @loc_availability = http_get.get(@target_url, {json_res: false, curl_opts: [get_standard_headers]})
        break if http_get.last_curl_status == "200"
        retry_count -= 1
      end
    end
    #    if @http_get.last_curl_status != 200
    #      http_get = HttpGet.new(%w[none none none], nil, {shuffle_prefs: true}, @logger)
    #      @loc_availability = http_get.get(@target_url, {json_res: false, curl_opts: [get_standard_headers]})
    #    end
    if (@loc_availability.nil? || @loc_availability.empty?)
      @logger.debug "Offers not available for zipcode - #{@zipcode}" 
      return
    end
   
  end
  
  def set_zip_code()
    
  end
  
  def extract_lease_data()
    
    listing_arr = []
    if(@loc_availability.nil? || @loc_availability.empty?)
      output = OpFormat.new  
      output.zip,output.brand = @zipcode,"NISSAN"                   #Populating instance with scraped data
      @logger.info "No lease data found for #{@zipcode}" 
      return OpFormat.convert_to_json(listing_arr << output,"lease_data")
    end
    nissan_offers_url = @config["nissan_offers"]
    resp = @http_get.get(nissan_offers_url, {json_res: false, curl_opts: [post_standard_headers]})  
    @response = Nokogiri::HTML(resp)
    offers = @response.search("//div[contains(@class,'toggle-lease')]") rescue nil
    if (offers.nil? || offers.size == 0 || offers.empty?)
      output = OpFormat.new  
      output.zip,output.brand = @zipcode,"NISSAN"   
      @logger.error "Error - No lease data found"
      return OpFormat.convert_to_json(listing_arr << output,"lease_data")  
    end
    #    batch = Array.new
    offers.each do|offer|
      #      break
      @logger.debug "Grabbing offers for - #{@zipcode}" 
      lease_data = offer.search(".//a[contains(@class,'open-offer_details')]")[0]
      lease_url = @config["lease_url"]
      response = @http_get.get(lease_url, {json_res: false, curl_opts: [get_lease_headers(lease_data)], tag: "OFFER_DETAILS_URL"})
      #      batch << {url: lease_url, tag: "OFFER_DETAILS_URL", json_res: false, curl_opts: [get_lease_headers(lease_data)], inout_hash: {zip: @zipcode, brand: "Nissan"}}         #is_json = false , get_lease_headers(lease_data), "OFFER_DETAILS_MODEL"
      #    end
      #    @http_get.process_batch(batch, 10){|url,response,inout_hash|
      lease_reponse = Nokogiri::HTML(response)
      
      output = OpFormat.new                   #creating instance of OpFormat
      output.zip = @zipcode
      output.brand = "NISSAN"
      begin
        output.title1 = strip_special_chars(lease_reponse.search(".//div[@class='title']")[0].text) rescue nil
        output.title2 = "LEASE"
        title3 = lease_reponse.search(".//div[@class='title']//following-sibling::span[@class='modal-other-info']//preceding-sibling::p[1]")[0].text rescue nil
        if(!title3.nil?)
          output.title3 = strip_special_chars(lease_reponse.search(".//div[@class='title']//following-sibling::span[@class='modal-other-info']//preceding-sibling::p[1]")[0].text) rescue nil 
          output.offer4 = strip_special_chars(lease_reponse.search(".//p//following-sibling::p[1]")[0].text).gsub(/\n/, " ") rescue nil 
        else
          output.offer1 = nil
          output.offer4 = strip_special_chars(lease_reponse.search(".//div[@class='title']//following-sibling::p").text.split("\n").join(".")) rescue nil
        end
        tempstr1 = strip_special_chars(lease_reponse.search(".//span[@class='modal-other-info']")[0].text).gsub(/\n/, " ") rescue ""
        tempstr2 = strip_special_chars(lease_reponse.search(".//span[@class='modal-other-info']")[1].text).gsub(/\n/, " ") rescue ""
        output.offer1 = tempstr1 + " " + tempstr2 rescue nil
        output.offer2 = strip_special_chars(lease_reponse.search(".//span[@class='modal-other-info']")[2].text).gsub(/\n/, " ") rescue ""
        output.disclaimer1 = lease_reponse.search(".//div[contains(@class,'ps')]/p | .//div[contains(@class,'ps')]")[0].text.strip.gsub(/\n/, " ") rescue nil
        output.msrp = output.disclaimer1.scan(/\$\d+.\d+ MSRP/)[0].gsub(/\$|,| |MSRP/,'')
        output.offer_type = "LEASE"
        model_code = output.disclaimer1.scan(/model\s(\d+)\s/).flatten[0] rescue nil
        output.model_details = "Model Code - #{model_code}" if model_code != nil rescue nil
        output.acquisition_fee = output.disclaimer1.scan(/a (\$\d+) .*acquisition fee/).flatten[0] rescue nil
        output.mileage_charge = output.disclaimer1.scan(/\$\d+.\d+ per mile.*miles per year/)[0] rescue nil
        end_date = output.disclaimer1.scan(/Offer ends \d+.\d+.\d+/)[0].gsub(/Offer ends /,'') rescue ""
        output.offer_end_date = Date.strptime("#{end_date}", "%m/%d/%Y").to_s rescue nil
        output.down_payment = output.disclaimer1.match(/(\$[\d\,]+) consumer down payment/)[1] rescue nil
        (output.disclaimer1.include? "Excludes taxes")? (output.tax_registration_exclusion = "Y") : (output.tax_registration_exclusion = "N") rescue nil
        if lease_reponse.search(".//span[@class='modal-other-info']").size >= 4
          check_offer =  strip_special_chars(lease_reponse.search(".//span[@class='modal-other-info']")[3].text).gsub(/\n/, " ")
          output.offer3 = check_offer if (tempstr1 != check_offer) rescue ""
        end
        output.emi = output.offer1.scan(/\$\d+/)[0].split("$").last 
        output.emi_months = output.offer1.scan(/ \d+ /)[0].gsub(/ /,'')
        output.due_at_signing = output.offer2.scan(/\$\d+.\d+/)[0].gsub(/\$|,/,'')
      rescue Exception => e
        @logger.debug "Error to grab listings- #{e.message} - #{e.backtrace.join("\n")}"
        @logger.error "Error in  Fetching data for zipcode = #{@zipcode}"
      end
      listing_arr << output
      @logger.debug "Current listings in array - #{listing_arr.size}"
      #    }
    end
    #        clr_cookie
    @logger.info "Total #{listing_arr.size} records found for #{@zipcode}" 
    return OpFormat.convert_to_json(listing_arr , "lease_data")
  end
  
  def extract_finance_data()
    finance_output_data = []
    if(@loc_availability.nil? || @loc_availability.empty?)
      output = OpFormat.new  
      output.zip,output.brand = @zipcode,"NISSAN"
      @logger.info "No finance data found for #{@zipcode}" 
      return OpFormat.convert_to_json(finance_output_data << output ,"finance_data")
    end
    offers = @response.search("//div[contains(@class,'toggle-apr')] | //div[contains(@class,'toggle-cash')] | //div[contains(@class,'toggle-special')]") rescue nil
    if (offers.nil? || offers.size == 0 || offers.empty?)
      output = OpFormat.new  
      output.zip,output.brand = @zipcode,"NISSAN"   
      @logger.error "Error - No finance data found"
      return OpFormat.convert_to_json(finance_output_data << output,"lease_data")  
    end
    #     batch = Array.new
    offers.each do|offer|
      @logger.debug "Grabbing offers for - #{@zipcode}" 
      offer_type = offer.search(".//a[contains(@class,'open-offer_details')]/@data-offrtyp")[0].text
      next if offer_type.downcase.include? "lease"
      
      #      next if ((offer_type.downcase.include? "cash") || (offer_type.downcase.include? "apr"))
      offer_data = offer.search(".//a[contains(@class,'open-offer_details')]")[0]
      offers_url = @config["lease_url"]
      response = @http_get.get(offers_url, {json_res: false, curl_opts: [get_lease_headers(offer_data)], tag: "OFFER_DETAILS_URL"})
      #      batch << {url: lease_url, tag: "OFFER_DETAILS_URL", json_res: false, curl_opts: [get_lease_headers(lease_data)], inout_hash: {zip: @zipcode, brand: "Nissan"}}         #is_json = false , get_lease_headers(lease_data), "OFFER_DETAILS_MODEL"
      #    end
      #    @http_get.process_batch(batch, 10){|url,response,inout_hash|
      lease_reponse = Nokogiri::HTML(response)
      
      output = OpFormat.new                   #creating instance of OpFormat
      output.zip = @zipcode
      output.brand = "NISSAN"
      begin
        output.title1 = strip_special_chars(lease_reponse.search(".//div[@class='title']")[0].text) rescue nil
        output.title2 = offer_type
        #        output.offer_type = offer_type
        #        next if !offer_type.downcase.include? "saving"
        if (offer_type.downcase.include? "cash") || (offer_type.downcase.include? "msrp")
          output.offer_type = "Other"
          output.offer1 = strip_special_chars(lease_reponse.search(".//span[@class='modal-other-info']")[0].text).gsub(/\n/, " ") rescue ""
          output.offer2 = strip_special_chars(lease_reponse.search(".//div[@class='title']//following-sibling::p")[0].text.split("\n").join("")) rescue nil
          output.disclaimer1 = lease_reponse.search(".//div[contains(@class,'ps')]/p | .//div[contains(@class,'ps')]")[0].text.strip.gsub(/\n/, " ") rescue nil
          start_date = output.disclaimer1.scan(/Offer valid from \d+.\d+.\d+/)[0].gsub(/Offer valid from /,'') rescue ""
          output.offer_start_date = Date.strptime("#{start_date}", "%m/%d/%Y").to_s rescue nil
          end_date = output.disclaimer1.scan(/.\d+ through \d+.\d+.\d+/)[0].gsub(/.\d+ through /,'') rescue ""
          output.offer_end_date = Date.strptime("#{end_date}", "%m/%d/%Y").to_s rescue nil
          output.cashback_amount = output.offer1.match(/(\$[\d\,]+) Bonus Cash/)[1] rescue nil 
        elsif offer_type.downcase.include? "apr"
          output.offer_type = "Finance" 
          title3 = lease_reponse.search(".//div[@class='title']//following-sibling::span[@class='modal-other-info']//preceding-sibling::p[1]")[0].text rescue nil
          if(!title3.nil?)
            output.title3 = strip_special_chars(lease_reponse.search(".//div[@class='title']//following-sibling::span[@class='modal-other-info']//preceding-sibling::p[1]")[0].text) rescue nil 
            output.offer4 = strip_special_chars(lease_reponse.search(".//p//following-sibling::p[1]")[0].text).gsub(/\n/, " ") rescue nil 
          else
            output.offer1 = nil
            output.offer4 = strip_special_chars(lease_reponse.search(".//div[@class='title']//following-sibling::p")[0].text.split("\n").join(".")) rescue nil
          end
          tempstr1 = strip_special_chars(lease_reponse.search(".//span[@class='modal-other-info']")[0].text).gsub(/\n/, " ") rescue ""
          tempstr2 = strip_special_chars(lease_reponse.search(".//span[@class='modal-other-info']")[1].text).gsub(/\n/, " ") rescue ""
          output.offer1 = tempstr1 + " " + tempstr2 rescue nil
          output.offer2 = strip_special_chars(lease_reponse.search(".//span[@class='modal-other-info']")[2].text).gsub(/\n/, " ") rescue ""
          output.emi_months = output.offer1.scan(/\d+ MONTHS/)[0].gsub(/ MONTHS/,'') rescue ""
          output.disclaimer1 = lease_reponse.search(".//div[contains(@class,'ps')]/p | .//div[contains(@class,'ps')]")[0].text.strip.gsub(/\n/, " ") rescue nil
          end_date = output.disclaimer1.scan(/Offers end \d+.\d+.\d+/)[0].gsub(/Offers end /,'') rescue ""
          output.offer_end_date = Date.strptime("#{end_date}", "%m/%d/%Y").to_s rescue nil
          if lease_reponse.search(".//span[@class='modal-other-info']").size >= 4
            check_offer =  strip_special_chars(lease_reponse.search(".//span[@class='modal-other-info']")[3].text).gsub(/\n/, " ")
            output.offer3 = check_offer if (tempstr1 != check_offer) rescue ""
          end
        else
          other_offers(output, lease_reponse, offer_type)
        end
      rescue Exception => e
        @logger.debug "Error to grab listings- #{e.message} - #{e.backtrace.join("\n")}"
        @logger.error "Error in  Fetching data for zipcode = #{@zipcode}"
      end
      finance_output_data << output
      @logger.debug "Current listings in array - #{finance_output_data.size}"
      #    }
    end
    clr_cookie
    @logger.info "Total #{finance_output_data.size} records found for #{@zipcode}" 
    return OpFormat.convert_to_json(finance_output_data , "finance_data")
  end
  
  def other_offers(output,response, off_type)
    output.offer_type = "Other"
    unless (response.search(".//div[contains(@class,'ps')]/p | .//div[contains(@class,'ps')]").empty?)||(response.search(".//div[contains(@class,'ps')]/p | .//div[contains(@class,'ps')]").nil?)
      b=response.search(".//div[contains(@class,'ps')]/p | .//div[contains(@class,'ps')]")[0].inner_html.split("<p>")
      b.delete("") if b.include?("")
      output.disclaimer1 = strip_special_chars(b[0]).gsub(/\<br\>|\<\/p\>|\n/,"") rescue nil
      output.disclaimer2 = strip_special_chars(b[1]).gsub(/\<br\>|\<\/p\>|\n/,"") rescue nil
      output.disclaimer3 = strip_special_chars(b[2]).gsub(/\<br\>|\<\/p\>|\n/,"") rescue nil
      output.disclaimer4 = strip_special_chars(b[3]).gsub(/\<br\>|\<\/p\>|\n/,"") rescue nil
      output.disclaimer5 = strip_special_chars(b[4]).gsub(/\<br\>|\<\/p\>|\n/,"") rescue nil
      if !response.search(".//div[@class='masthack']").empty?
        a=response.search(".//div[@class='masthack']")[0].inner_html.split("<br>")
        a.delete("---- ") if a.include? "---- "
        output.offer1 = strip_special_chars(a[0]).gsub(/\<sup\>|\<\/sup\>|\-/,"") rescue nil
        output.offer2 = strip_special_chars(a[1]).gsub(/\<sup\>|\<\/sup\>|\-/,"") rescue nil
        output.offer3 = strip_special_chars(a[2]).gsub(/\<sup\>|\<\/sup\>|\-/,"") rescue nil
        output.offer4 = strip_special_chars(a[3]).gsub(/\<sup\>|\<\/sup\>|\-/,"") rescue nil
        output.offer5 = strip_special_chars(a[4]).gsub(/\<sup\>|\<\/sup\>|\-/,"") rescue nil
      else
        output.offer1 = output.disclaimer1.match(/OR (\$.*?cash back)/)[1] rescue nil  
        output.offer2 = strip_special_chars(b[1]).split("<br>").first.match(/(\$.*)/)[1].strip rescue nil
        output.offer3 = strip_special_chars(b[2]).split("<br>").first.match(/(\$.*)/)[1].strip rescue nil 
        output.offer4 = strip_special_chars(b[3]).split("<br>").first.match(/(\$.*)/)[1].strip rescue nil 
        output.offer5 = strip_special_chars(b[4]).split("<br>").first.match(/(\$.*)/)[1].gsub(/available.*?\./,'').strip  rescue nil
        
        output.offer6 = response.search(".//span[@class='modal-other-info']//text()")[1..3].text.strip rescue nil
      end
      disclaimer = response.search(".//div[contains(@class,'ps')]/p | .//div[contains(@class,'ps')]")[0].text.strip.gsub(/\n/, " ") rescue nil
      end_date = disclaimer.scan(/Offers end \d+.\d+.\d+|Ends \d+.\d+.\d+/)[0].gsub(/Offers end |Ends /,'') rescue ""
      if end_date == ""
        start_date = disclaimer.scan(/Offer valid from \d+.\d+.\d+/)[0].gsub(/Offer valid from /,'') rescue ""
        output.offer_start_date = Date.strptime("#{start_date}", "%m/%d/%Y").to_s rescue nil
        end_date = disclaimer.scan(/.\d+ through \d+.\d+.\d+/)[0].gsub(/.\d+ through /,'') rescue ""
      end
      output.offer_end_date = Date.strptime("#{end_date}", "%m/%d/%Y").to_s rescue nil
    end
  end
  
  def strip_special_chars(text)
    return nil if !text
    clean_text = ""
    text.each_byte { |x|  clean_text << x unless x > 127   }
    clean_text.gsub(/\[1\]/,"").gsub(/\n/,"")
    return clean_text
  end
  
  def get_standard_headers
    @config["nissan_headers"].join(" ") + " -b #{in_cookie()} -c #{out_cookie()}"
  end
  
  def post_standard_headers
    @config["nissan_post_headers"].join(" ") + " -b #{in_cookie()} -c #{out_cookie()}"
  end
  
  def get_lease_headers(lease_data)
    @config["nissan_lease_headers"].join(" ").gsub("#vsp#",lease_data["data-offer_type"])
    .gsub("#type#",lease_data["data-offer_order"])
    .gsub("#url#",lease_data["data-offer_url"])
    .gsub("#year#",lease_data["data-offer_year"])
    .gsub("#section#",lease_data["data-offer_section"])
    .gsub("#position#",lease_data["data-pfa_position"]) + " -b #{in_cookie()} -c #{out_cookie()}"
  end
  
  def in_cookie
    "#{@output_dir}/#{@uniq_id}/cookie_#{@cookie_index}"  
  end

  def out_cookie
    @cookie_index += 1
    "#{@output_dir}/#{@uniq_id}/cookie_#{@cookie_index}"  
  end
  
  #  def create_ck_dir
  #    `mkdir -p '#{@output_dir}'`
  #  end
  
  def clr_cookie
    `rm -rf '#{@output_dir}'`
  end
  
end