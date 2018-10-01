require_relative "../../../lib/extracters/base/base_extractor"
require_relative "../../../lib/utils/http_get"
require "pry"
require "awesome_print"
require 'logging'
require 'logger'
require 'nokogiri'
require 'date'
require_relative "op_format.rb"

class Extractor < BaseExtractor
  
  def initialize(make, zip)
    super(make, zip)
    @http_get = HttpGet.new(%w[shader shader shader squid squid shader], nil, {shuffle_prefs: true}, @logger)
  end
  
  def load_target_page()
    @target_url = @config["target_page"]
    @response = @http_get.get(@target_url, {json_res: false, curl_opts: [get_standard_headers]})
    @response_doc = Nokogiri::HTML(@response)
  end
  
  def set_zip_code()
    
  end
  
  def extract_lease_data()
      lease_output_data = []
      if(@response.nil? || @response.empty?)
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "SMART"
      @logger.info "No lease data found for #{@zipcode}" 
      lease_output_data << output 
      return OpFormat.convert_to_json(lease_output_data,"lease_data")
    end
        @response_doc.xpath("//ul[@class='offers-list']").each{ |offers| 
          
        offers.xpath("./li").each{|details|
         
        offer_desc = details.xpath(".//ul[@class='offer-terms-info']/strong").text.downcase
        next if !offer_desc.include? "lease"
        output = OpFormat.new                   #creating instance of OpFormat
        output.zip = @zipcode
        output.brand = "SMART"
        begin
        output.offer_type = "Lease"
        output.emi = details.xpath(".//p[@class='offer-terms-price']/span").text.scan(/\$\d+\//)[0].gsub(/\/|\$/,'')
        output.emi_months = details.xpath(".//p[@class='offer-terms-price']/span").text.scan(/ \d+/)[0].gsub(/ /,'')
        output.title1 = details.xpath("./h3").text
        output.title2 = details.xpath(".//ul[@class='offer-terms-info']/strong").text
        output.offer1 = details.xpath(".//p[@class='offer-terms-price']/span").text
        output.title3 = details.xpath(".//div[@class='offer-further-info']/figcaption").text.strip
#        @offer1 = details.xpath(".//span[@class='footnote-details']/p").text.gsub(/\n|\s{2,}/,'')
        index = details.xpath(".//span[@class='footnote-details']/p").size
        output.disclaimer1 = details.xpath(".//span[@class='footnote-details']/p[3]").text.gsub(/\n|\s{2,}/,'')
        if index == 4
          output.disclaimer2 = details.xpath(".//span[@class='footnote-details']/p").text.split("\n").last.strip
        else
          if index == 5
          output.disclaimer2 = details.xpath(".//span[@class='footnote-details']/p[4]").text.gsub(/\n|\s{2,}/,'')
          output.disclaimer3 = details.xpath(".//span[@class='footnote-details']/p").text.split("\n").last.strip
          end
        end 
        (output.disclaimer1.include? "Excludes title, taxes")? (output.tax_registration_exclusion = "Y") : (output.tax_registration_exclusion = "N") rescue nil
        output.disposition_fee = output.disclaimer1.match(/(\$[\d\.\,]+) vehicle turn-in fee/)[1] rescue nil
        output.mileage_charge = output.disclaimer1.scan(/\$\d+.\d+\/mile over.*miles/)[0] rescue nil
        output.msrp = output.disclaimer1.scan(/MSRP of \$\d+.\d+/)[0].split("$").last.gsub(/,/,'') rescue ""
        output.acquisition_fee = output.disclaimer1.scan(/.\d+ acquisition fee/)[0].split(" ").first.gsub(/^.|,/,'') rescue ""
        output.due_at_signing = output.disclaimer1.match(/due at signing includes (\$[\d\.\,]+)/)[1] rescue nil
        offer_end_date = output.disclaimer1.scan(/participating dealers through \w+ \d+. \d+/)[0].split("through ").last rescue ""
        output.offer_end_date = DateTime.parse(offer_end_date).to_s.split("T").first rescue ""
        rescue Exception => e
        @logger.debug "Error to grab listings- #{e.message} - #{e.backtrace.join("\n")}"
        @logger.error "Error in  Fetching data for zipcode = #{@zipcode}"
      end
        lease_output_data << output
        }
        }
       @logger.info "Total #{lease_output_data.size} records found for #{@zipcode}" 
    return OpFormat.convert_to_json(lease_output_data , "lease_data")   #Converting array of output objects in to json format
  end
  
  def extract_finance_data()
    finance_output_data = []
    if(@response.nil? || @response.empty?)
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "SMART"
      @logger.info "No finance data found for #{@zipcode}" 
      finance_output_data << output 
      return OpFormat.convert_to_json(finance_output_data,"finance_data")
    end
    @response_doc.xpath("//ul[@class='offers-list']").each{ |offers| 
     offers.xpath("./li").each{|details|
     offer_desc = details.xpath(".//ul[@class='offer-terms-info']/strong").text.downcase
     next if offer_desc.include? "lease"
        output = OpFormat.new                   #creating instance of OpFormat
        output.zip = @zipcode
        output.brand = "SMART"
        output.offer_type = "Finance"
        begin
        output.title1 = details.xpath("./h3").text
        output.title2 = details.xpath(".//ul[@class='offer-terms-info']/strong").text
        output.offer1 = details.xpath(".//p[@class='offer-terms-price']/span").text
        output.offer2 = details.xpath(".//p[@class='offer-terms-extras']").text
        output.title3 = details.xpath(".//div[@class='offer-further-info']/figcaption").text.strip
        output.disclaimer1 = details.xpath(".//span[@class='footnote-details']/p").text.gsub(/\n|\s{2,}/,'')
        output.apr_rate = output.disclaimer1.scan(/([\d\.]+\%) percent APR/).flatten[0] + "|" + output.disclaimer1.scan(/([\d\.]+\%) percent APR/).flatten[1].sub(/^\./,'') rescue nil
        output.emi_months = output.disclaimer1.scan(/APR for (\d+) months/).flatten[0] + "|" + output.disclaimer1.scan(/APR for (\d+) months/).flatten[1] rescue nil
        offer_end_date = output.disclaimer1.scan(/Must take delivery of vehicle by \w+ \d+. \d+/)[0].split("vehicle by ").last rescue ""
        output.offer_end_date = DateTime.parse(offer_end_date).to_s.split("T").first rescue ""
        rescue Exception => e
        @logger.debug "Error to grab listings- #{e.message} - #{e.backtrace.join("\n")}"
        @logger.error "Error in  Fetching data for zipcode = #{@zipcode}"
      end
       finance_output_data << output 
      }
    }
    @logger.info "Total #{finance_output_data.size} records found for #{@zipcode}" 
    return OpFormat.convert_to_json(finance_output_data , "finance_data")   #Converting array of output objects in to json format
  end
  
  def get_standard_headers
    @config["headers"].join(" ")
  end
end