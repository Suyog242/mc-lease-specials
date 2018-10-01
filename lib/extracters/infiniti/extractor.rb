require_relative "../../../lib/extracters/base/base_extractor"
require_relative "../../../lib/utils/http_get"
require_relative "op_format.rb"
#require_relative "../../../lib/config/bmw.yml"
require "pry"
require "awesome_print"
require 'logging'
require 'logger'

class Extractor < BaseExtractor
  def initialize(make, zipcode)
    super(make, zipcode)
    @http_get = HttpGet.new(%w[squid squid shader shader shader shader ], nil, {shuffle_prefs: true}, @logger)
    @output_dir = "/tmp/cookie/infiniti/#{@zipcode}"
    @cookie_index =  1
    @type = "Lease"
    @lease_output_data,@fianance_output_data ,@start, @size  = [],[], 0, 20
  end
  
  def load_target_page()
    creatae_ck_dir
    home_page_response = @http_get.get('https://www.infinitiusa.com/', {json_res: false, curl_opts: [@config["test_headers"].join(" "), " -c #{out_cookie()}"],tag: "CURL- Target"})
    api_info = JSON.parse(home_page_response.gsub(/\n|\s|\t/,"").match(/apigee.*?}/)[0].gsub("apigee\":",""))
    @api_key, @client_key =  api_info["apiKey"], api_info["clientKey"]
  end
  
  def set_zip_code()
    @type =  @type == "Lease" ? "Lease" : "Purchase" 
    @offer_url = @config["offer_url"].gsub(/###TYPE###/, @type).gsub(/###ZIPCODE###/,@zipcode.to_s).gsub(/###START###/, "#{@start}").gsub(/###SIZE###/, "#{@size}")
    headers = @config["api_headers"].join(" ").gsub(/###CLIENT_KEY###/, @client_key).gsub(/###API_KEY###/, @api_key)
    @response = @http_get.get(@offer_url, {json_res: true, curl_opts: [headers ],tag: "CURL- #{@zipcode}"}) #, "-b #{in_cookie()}"
  end
  
  
  def extract_lease_data()
    begin
      @response["offers"].each{ |offer|
        output = OpFormat.new
        if offer["offerType"].downcase.include? "lease"
          output.zip =  @zipcode
          output.offer_type = "Lease"
          output.brand = "INFINITI"
          output.emi = "#{offer["title"]["headline"].gsub(",","").match(/(\d+)\s+\/\s+Month Lease/)[1]}"
          output.emi_months = offer["title"]["strapline"].match(/(\d+)\sMonths/)[1]
          output.down_payment = offer["details"].gsub(",","").match(/(\d+) consumer down payment/)[1]
          offer_end_date = offer["legals"]["priority"].match(/Offer ends\s+(.*)./)[1].to_s rescue nil
          output.model_details =  offer["model"]["code"]
          output.title1 = offer["heading"]
          output.offer1 = offer["title"]["headline"] 
          output.offer2 = offer["title"]["strapline"]
          output.disclaimer1 =  offer["details"]
          output.mileage_charge = offer["details"].gsub(",","").match(/\$[\d\.]+\/mile for mileage over \d+ miles\/year/)[0]
          output.acquisition_fee =  offer["details"].gsub(",","").match(/.*includes a \$(\d+)\s+.*acquisition/)[1]
          output.msrp = offer["details"].gsub(",","").match(/MSRP\s+\$(\d+)\s+includes/)[1]
          output.tax_registration_exclusion = offer["details"].include?("Excludes, taxes, title & license") ? "Y" : "N"
          output.offer_end_date = Date.strptime(offer_end_date, '%m/%d/%y').to_s  rescue nil if !offer_end_date.nil?
          @lease_output_data << output
        end
      }
      if @lease_output_data.size < @response["totalResults"].to_i 
        @start = @size
        @size = @response["totalResults"]
        set_zip_code()
        extract_lease_data()
      end
      if @lease_output_data.flatten.empty?
        output = OpFormat.new
        output.zip = @zipcode
        output.offer_type = "Lease"
        output.brand = "INFINITI"
        @lease_output_data << output
      end
      return OpFormat.convert_to_json(@lease_output_data, "lease_data")
    rescue Exception => e
      @logger.error e.backtrace
      lease_output_data  = []
      output = OpFormat.new
      output.zip = @zipcode
      output.offer_type = "Lease"
      output.brand = "INFINITI"
      lease_output_data << output
      return OpFormat.convert_to_json(lease_output_data, "lease_data")
    end
  end
  
  def extract_finance_data()
    @finance_output_data, @start, @size = [], 0,20
    @type = "Purchase"
    load_target_page
    set_zip_code()
    extract_data()
  end
  
  def extract_data()
    begin
      @response["offers"].each{ |offer|
        output = OpFormat.new
        if offer["offerType"].downcase.include? "purchase"
          output.zip =  @zipcode
          output.offer_type = "Finance"
          output.brand = "INFINITI"
          output.apr_rate = "#{offer["title"]["headline"].gsub(",","").match(/(\d+[.]\d+)/)[1]}%" rescue nil
          output.emi_months = offer["title"]["strapline"].match(/(\d+)\sMonths/)[1] rescue nil
          output.model_details =  offer["model"]["code"]
          offer_end_date = offer["legals"]["priority"].match(/Offer ends\s+(\d+\/\d+\/\d+)./)[1].to_s rescue nil
          output.title1 = offer["heading"] rescue nil
          output.offer1 = offer["title"]["headline"] rescue nil
          output.offer2 = offer["title"]["strapline"] rescue nil
          output.disclaimer1 =  offer["details"] rescue nil
          output.offer_end_date = Date.strptime(offer_end_date, '%m/%d/%y').to_s  rescue nil  if !offer_end_date.nil?
          @finance_output_data << output
        end
      }
      if @finance_output_data.size < @response["totalResults"].to_i 
        @start = @size
        @size = @response["totalResults"]
        set_zip_code()
        extract_data()
      end
      if @finance_output_data.flatten.empty?
        output = OpFormat.new
        output.zip = @zipcode
        output.offer_type = "Finance"
        output.brand = "INFINITI"
        @finance_output_data << output
      end
      
      return OpFormat.convert_to_json(@finance_output_data, "finance_data")
    rescue Exception => e
      @logger.error e.backtrace
      finance_output_data  = []
      output = OpFormat.new
      output.zip = @zipcode
      output.offer_type = "Finance"
      output.brand = "INFINITI"
      finance_output_data << output
      return OpFormat.convert_to_json(finance_output_data, "finance_data")
    end
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

