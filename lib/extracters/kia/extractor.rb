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
    @http_get = HttpGet.new(%w[shader shader shader squid squid shader], nil, {shuffle_prefs: true}, @logger)
    
  end
  
  def load_target_page()
    @post_data = Array.new
    @host = @config["target_page"]
    target_url = "#{@host}/data/dealers/dealerInventoryDropDowns"
  
    @target_response = (@http_get.get(target_url,  {
          json_res:true, curl_opts: [get_headers], tag: "GET_ALL_THE_SERIES" }))
  
    if !@target_response.nil?
      @target_response["modelYears"].each{|series| 
        @post_data << {"seriesId" => series["series"], "year" => series["years"].first}
      }
   
      @post_data.uniq!{|x| x["seriesId"]}
    end
  
  end
  
  def set_zip_code()
    
  end
  
  def extract_lease_data()
    listing_arr = Array.new
    data = Hash.new 
    data["vehicles"] = @post_data
    data["categories"] = [2]
    if(@target_response.nil? || @target_response.empty?)
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "KIA"
      @logger.info "No lease data found for #{@zipcode}" 
      listing_arr << output 
      return OpFormat.convert_to_json(listing_arr)
    end
    ["2018"].each{|year|
      offers_url = "#{@host}/data/offers/#{@zipcode}"
      @referer = "#{@host}/offers/#{year}/#{@zipcode}?series=all&offers=2"
                
      headers = [get_listing_headers.gsub(/##REFERER##/, @referer), 
        "--data-binary '#{data.to_json}' --compressed" ]
                
      @offers_response = @http_get.get(offers_url,  {
          json_res:true, curl_opts: headers, tag: "CURL_INITIAL" }){ |status, resp|
        block_test = false
        if status.to_s == "500" && resp.size > 0
          block_test = true
        end
        block_test
      }
                
      @not_valid_vins << @zipcode if @http_get.last_curl_status == "500"
      next if @http_get.last_curl_status != "200" || @offers_response.nil? || @offers_response["result"].nil? || @offers_response["result"]["vehicle"].empty?
                
      batch = Array.new

      @offers_response["result"]["vehicle"].each{|vehicle|
        vehicle["offers"].each{|offer|
          offer_id = offer["offerId"]
          vehicle_id = offer["vehicleId"]
          url = "#{@host}/partials/offers/#{@zipcode}/#{offer_id}/#{vehicle_id}/offer-details.hbs"
      
          batch << { tag: "CURL_FOR_OFFERID_#{offer_id}", json_res: false, 
            curl_opts: get_standard_headers.gsub(/##REFERER##/, @referer), url: url, inout_hash: {zip: @zipcode, brand: "Kia"} }
        }
      }
  
      @http_get.process_batch(batch, 10){|url, response, inout_hash|
        
        output = OpFormat.new 
        output.disclaimer1 = ""
        parsed_res = Nokogiri::HTML(response)
        output.brand = "KIA"
        output.zip = @zipcode
        output.offer_type = "Lease"
        output.title1 = parsed_res.xpath("//div[@class='offer-name']").text rescue nil
        output.title2 = parsed_res.xpath("//div[@class='model-info']").text rescue nil
        output.offer1 = parsed_res.xpath("//div[@class='offer-details']/div")[0].text rescue nil
        output.offer2 = parsed_res.xpath("//div[@class='offer-details']/div")[1].text rescue nil
        output.offer3 = parsed_res.xpath("//ul[@class='details-description']").text.strip rescue nil
        output.emi_months = output.offer2[/\d+ Months/].gsub(/ Months/,'') rescue nil
        output.emi = output.offer1[/\$\d+\/month/].gsub(/\$|\/month/,'') rescue nil
        output.due_at_signing = output.offer3[/\$\d+.\d+ Due at Signing/].gsub(/\$|,| Due at Signing/,'') rescue nil
        #output.msrp = output.disclaimer1[/MSRP \$\d+.\d+/].gsub(/\$|,|MSRP /,'') rescue nil
        desc = parsed_res.xpath("//span[@class='disclaimer']/p") rescue nil
        desc.each{|p| output.disclaimer1 += p.text.strip} if !desc.nil?
        output.msrp = output.disclaimer1[/MSRP \$\d+.\d+/].gsub(/\$|,|MSRP /,'') rescue nil
        offer_end_date = output.disclaimer1[/from retail stock by \d+.\d+.\d+/].gsub(/from retail stock by /,'') rescue nil
        output.model_details, output.acquisition_fee, output.mileage_charge, output.disposition_fee = output.disclaimer1.match(/\(Model\s(.*?)\).*?\$(\d+) acquisition fee.*(\$[\d+\.\d+].*\/year).*?\$(\d+)\s+termination fee*/)[1..4].map{|v| v.strip}  rescue nil
        output.tax_registration_exclusion = output.disclaimer1.include?("excludes taxes, title") ? "Y" : "N"  
        output.offer_end_date = Date.strptime(offer_end_date, '%m/%d/%y').to_s  if !offer_end_date.nil?
        listing_arr << output #[inout_hash[:zip], inout_hash[:brand], title_1, title_2, offer_1, offer_2, offer_3, desclaimer]
      }
    }
    listing_arr.uniq!
    @logger.info "Total #{listing_arr.size} records found for #{@zipcode}"
   OpFormat.convert_to_json(listing_arr, "lease_data") #Converting array of output objects in to json format 
  end
  
  def extract_finance_data()
    finance_output_data = []
    data = Hash.new 
    data["vehicles"] = @post_data
    data["categories"] = [1,3]
    if(@target_response.nil? || @target_response.empty?)
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "KIA"
      @logger.info "No lease data found for #{@zipcode}" 
      listing_arr << output 
      return OpFormat.convert_to_json(listing_arr)
    end
    ["2018"].each{|year|
      offers_url = "#{@host}/data/offers/#{@zipcode}"
      @referer = "#{@host}/offers/#{year}/#{@zipcode}?series=all&offers=3"
                
      headers = [get_listing_headers.gsub(/##REFERER##/, @referer), 
        "--data-binary '#{data.to_json}' --compressed" ]
                
      @offers_response = @http_get.get(offers_url,  {
          json_res:true, curl_opts: headers, tag: "CURL_INITIAL" }){ |status, resp|
        block_test = false
        if status.to_s == "500" && resp.size > 0
          block_test = true
        end
        block_test
      }
      @not_valid_vins << @zipcode if @http_get.last_curl_status == "500"
      next if @http_get.last_curl_status != "200" || @offers_response.nil? || @offers_response["result"].nil? || @offers_response["result"]["vehicle"].empty?
      batch = Array.new
      @offers_response["result"]["vehicle"].each{|vehicle|
        vehicle["offers"].each{|offer|
          offer_id = offer["offerId"]
          vehicle_id = offer["vehicleId"]
          url = "#{@host}/partials/offers/#{@zipcode}/#{offer_id}/#{vehicle_id}/offer-details.hbs"
      
          batch << { tag: "CURL_FOR_OFFERID_#{offer_id}", json_res: false, 
            curl_opts: get_standard_headers.gsub(/##REFERER##/, @referer), url: url, inout_hash: {zip: @zipcode, brand: "Kia"} }
        }
      }
  
      @http_get.process_batch(batch, 10){|url, response, inout_hash|
        apr_rates = []
        output = OpFormat.new 
        parsed_res = Nokogiri::HTML(response)
        get_data(parsed_res, output)
        apr_rates = output.disclaimer1.match(/availability\.(\d+.*\d+ months)/)[1].split("months.") rescue []
        apr_rates.each{|apr_rate|
          output = OpFormat.new 
          get_data(parsed_res, output)
          output.apr_rate , output.emi_months = apr_rate.gsub(",","").match(/(.*%).*up to (\d+)/)[1..2] rescue nil
          finance_output_data << output
        }
        finance_output_data << output if apr_rates.size < 1
         #[inout_hash[:zip], inout_hash[:brand], title_1, title_2, offer_1, offer_2, offer_3, desclaimer]
      }
    }
    finance_output_data.flatten.uniq
     @logger.info "Total #{finance_output_data.flatten.uniq.size} records found for #{@zipcode}"
   OpFormat.convert_to_json(finance_output_data.uniq, "finance_data") #Converting array of output objects in to json format
  end
  
  def get_data(parsed_res, output)
          output.disclaimer1 = ""
          output.zip = @zipcode
          output.brand = "KIA"
          output.title1 = parsed_res.xpath("//div[@class='offer-name']").text rescue nil
          output.offer_type =  output.title1.include?("Cash Offer") ? "Other" : "Finance"
          output.title2 = parsed_res.xpath("//div[@class='model-info']").text rescue nil
          output.offer1 = parsed_res.xpath("//div[@class='offer-details']/div")[0].text rescue nil
          output.cashback_amount = output.offer1.gsub(",","").match(/\$(\d+)\s+Cash Back/)[1] rescue nil
          output.offer2 = parsed_res.xpath("//div[@class='offer-details']/div")[1].text rescue nil
          output.offer3 = parsed_res.xpath("//ul[@class='details-description']").text.strip rescue nil
  #        output.emi_months = output.offer2[/\d+ Months/].gsub(/ Months/,'') rescue nil
  #        output.emi = output.offer1[/\$\d+\/month/].gsub(/\$|\/month/,'') rescue nil
          desc = parsed_res.xpath("//span[@class='disclaimer']/p") rescue nil
          desc.each{|p| output.disclaimer1 += p.text.strip} if !desc.nil?
          output.offer_start_date = output.disclaimer1[/retail stock from \d+.\d+.\d+/].gsub(/retail stock from /,'') rescue ""
          offer_end_date = output.disclaimer1[/retail stock from \d+.\d+.\d+ to \d+.\d+.\d+/].gsub(/retail stock from \d+.\d+.\d+ to/,'') rescue nil
          output.offer_end_date = Date.strptime(offer_end_date, '%m/%d/%y').to_s  rescue nil if !offer_end_date.nil?
  end
  
  
  def get_headers
    @config["target_page_headers"].join(" ")
  end
  
  def get_listing_headers
    @config["listing_page"].join(" ")
  end

  def get_standard_headers
    @config["lease_headers"].join(" ")
  end
end