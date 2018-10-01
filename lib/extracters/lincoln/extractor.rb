require 'json'
require 'ap'
require_relative "../../../lib/extracters/base/base_extractor"
require_relative "../../../lib/utils/http_get.rb"
require_relative "./op_format"
require 'uri'
require 'nokogiri'

class Extractor < BaseExtractor
  def initialize(make, zipcode)
    super(make, zipcode)
    @make = make
    @zip = zipcode
    @http_get = HttpGet.new(%w[shader shader shader squid squid shader], nil, {shuffle_prefs: true}, @logger)
  end
  
  def load_target_page()
    @model = []
    @domain = URI(@config["target_page"]).host
    response = @http_get.get(@config["target_page"], {
        json_res: false, 
        curl_opts: [get_standard_headers]
      })
    
    @noko_doc = Nokogiri::HTML(response)
    model_resp = @noko_doc.xpath(".//script[contains(text(),'Nameplates')]").text().strip
    model_resp_1 = model_resp.split("\r\n")[1].strip.gsub(".constant('Nameplates', ","")
    model_json = JSON.parse(model_resp_1.chomp(")"))
    model_ids = model_json.select{|x,y| x.has_key?("models") && !x["models"].nil?}.map{|d| d["id"]}
    
    model_ids.each{ |model_id|
      make, model, year = model_id.split('-')
      @model << {
        model: model,
        year: year
      }
    }
  end
  
  def set_zip_code()
    
  end
  
  def post_data(make, model, zip, year)
    post_hsh = {
      "appContext" => "ngbs_sploffr",
      "language" => "EN",
      "make" => make,
      "model" => model,
      "postalCode" => zip,
      "year" => year
    }
  
    params = ""
    post_hsh.each{ |k, v|
      params += "#{k}=#{CGI::escape(v)}&"
    }
    params.chop!
  end
  
  def extract_lease_data()
    lease_output_data = []
    @model.each{ |_car|
      lease_url = "#{@config["lease_base_url"]}#{post_data(@make.capitalize, _car[:model], @zipcode.to_s, _car[:year])}"
      @response = @http_get.get(lease_url, {
          json_res: true, 
          curl_opts: [get_standard_headers]
        })
      
      if !@response || @response["Response"]["status"] == "FAILURE" 
        output = OpFormat.new  
        output.zip = @zipcode                   #Populating instance with scraped data
        output.brand = "LINCOLN"
        @logger.info "No lease data found for #{@zipcode}" 
        lease_output_data << output 
        return OpFormat.convert_to_json(lease_output_data , "lease_data")
      end
      begin
        lease_offers = if @response["Response"]["Nameplate"]["Groups"].empty?
          @response["Response"]["Nameplate"]["Trims"]["Trim"].map{ |trim|
            trim["Groups"]["Group"].select{|x| x["Campaign"]["CampaignType"].include?("Lease") rescue nil}
          }.flatten.reject{|x| x.empty?} 
        else
          @response["Response"]["Nameplate"]["Groups"]["Group"].select{|x| x["Campaign"]["CampaignType"].include?("Lease") rescue nil}.reject{|x| x.empty?}
        end
      rescue 
        next if (@response["Response"]["Nameplate"]["Trims"].empty? || @response["Response"]["Nameplate"]["Groups"].empty?)
      end
      
      lease_offer_for_modal = []
      lease_offers.each{ |lease_offer|
        output = OpFormat.new                   #creating instance of OpFormat
        output.zip = @zipcode                   #Populating instance with scraped data
        output.brand = "LINCOLN"
        output.offer_start_date = lease_offer["Campaign"]["StartDate"] rescue nil
        output.offer_end_date = lease_offer["Campaign"]["EndDate"] rescue nil
        output.security_deposit = lease_offer["Campaign"]["SecurityDeposite"] rescue nil if !lease_offer["Campaign"]["SecurityDeposite"].empty?

        title1, title2 = lease_offer["Campaign"]["Name"].scan(/\>(.*?)\</).select{|x| !x[0].strip.empty?}.flatten rescue [nil, nil]
        offer1, offer2 = lease_offer["Campaign"]["Detail"].scan(/\>(.*?)\</).join('').split(/(?<=mos)\./) rescue [nil, nil]
        output.offer_type = "Lease"
        output.disposition_fee = lease_offer["Campaign"]["Disclaimer"].scan(/\$\d+ lease disposition .*vehicle\. /).first rescue nil
        output.mileage_charge = lease_offer["Campaign"]["Disclaimer"].scan(/.Lessee.*\mile./).first rescue nil
        output.due_at_signing = lease_offer["Campaign"]["CashDueAtSigning"] rescue nil
        output.tax_registration_exclusion = lease_offer["Campaign"]["Disclaimer"].scan(/Tax.*extra./).empty? ? "N" : "Y" rescue nil
        
        output.title1 = title1.gsub(/&amp;/, '&').strip rescue nil
        output.title2 = title2.gsub(/&amp;/, '&').strip rescue nil
        output.offer1 = offer1.strip rescue nil
        output.offer2 = offer2.strip rescue nil
        output.disclaimer1 = OpFormat.parse_text(lease_offer["Campaign"]["Disclaimer"]).gsub(/<("[^"]*"|'[^']*'|[^'">])*>/, '') rescue nil
        output.emi = lease_offer["Campaign"]["Payment"] rescue nil
        output.emi_months = lease_offer["Campaign"]["Term"] rescue nil
        output.model_details = @response["Response"]["Nameplate"]["model"] rescue nil
        output.cashback_amount = lease_offer["Campaign"]["Disclaimer"].scan(/\$.*cash back/).first.gsub(" total cash back",'') rescue nil
        
        lease_offer_for_modal << output  
      }  
      lease_output_data << lease_offer_for_modal if !lease_offer_for_modal.empty?
    }

    lease_output_data.flatten!
    OpFormat.convert_to_json(lease_output_data , "lease_data")   #Converting array of output objects in to json format
  end
  
  def  extract_finance_data
    @finance_output_data = []
    @model.each{ |_car|
      lease_url = "#{@config["lease_base_url"]}#{post_data(@make.capitalize, _car[:model], @zipcode.to_s, _car[:year])}"
      @response = @http_get.get(lease_url, {
          json_res: true, 
          curl_opts: [get_standard_headers]
        })
      if !@response
        output = OpFormat.new  
        output.zip = @zipcode                   #Populating instance with scraped data
        output.brand = "LINCOLN"
        @logger.info "No lease data found for #{@zipcode}" 
        @finance_output_data << output 
        return OpFormat.convert_to_json(@finance_output_data)
      end
      @offers = @response["Response"]["Nameplate"]["Groups"] rescue nil
      @model = @response["Response"]["Nameplate"]["model"] rescue nil
      trim_offer =  @response["Response"]["Nameplate"]["Trims"]["Trim"] rescue nil
      if @offers == "" && trim_offer && !trim_offer.is_a?(Hash)
        trim_offer.each{|main_offer|
          @offers = main_offer["Groups"]
          next if  @offers == "" || !@offers["Group"].is_a?(Hash)
          scrape_finance_data(@offers , lease_url)
        }
      else
        next if @offers == ""
        scrape_finance_data(@offers , lease_url)
      end
    }
    @finance_output_data.flatten! if !@finance_output_data.empty?
    OpFormat.convert_to_json(@finance_output_data , 'finance_data')   #Converting array of output objects in to json format
  end
  
  
  def scrape_finance_data(offers , url)
    offers["Group"].each{|group|
      next if group.is_a?(Array)
      if group["Campaign"]
        next if !group["Campaign"]["CampaignType"].include?("APR") 
        model_name = "#{group["Campaign"]["Name"]}".scan(/\>(.*?)\</).select{|x| !x[0].strip.empty?}.flatten.first rescue nil
        details = Nokogiri::HTML("#{group["Campaign"]["Detail"]}").text.split(/OR|\+|PLUS/)
        if details[1]
          output = OpFormat.new
          output.brand = "LINCOLN"
          output.title1 = "Cash offers"
          output.offer_type = "Other"
          output.apr_rate =  group["Campaign"]["APRRate"] rescue nil
          output.offer_start_date = group["Campaign"]["startDate"] rescue nil
          output.offer_end_date =  group["Campaign"]["endDate"] rescue nil
          output.cashback_amount = details[1].gsub(/Cash Back|Bonus Cash/i,'').strip rescue nil
          output.title2 =  model_name
          output.model_details = @model
          output.offer1 = details[1].strip rescue nil
          output.offer_start_date = group["Campaign"]["StartDate"] rescue nil
          output.offer_end_date = group["Campaign"]["EndDate"] rescue nil
          output.zip = @zip
          @finance_output_data << output
        end
        output = OpFormat.new
        output.brand = "LINCOLN"
        output.apr_rate = group["Campaign"]["APRRate"] rescue nil
        output.emi_months = group["Campaign"]["Term"].to_s rescue nil
        output.title1 = "Retail offers"
        output.model_details = @model
        output.offer_type = "Finance"
        output.title2 =  model_name 
        output.offer1 = details[0]
        output.offer_start_date = group["Campaign"]["StartDate"]  rescue nil
        output.offer_end_date = group["Campaign"]["EndDate"] rescue nil
        output.zip = @zip
        output.disclaimer1 = OpFormat.parse_text(group["Campaign"]["Disclaimer"]).gsub(/<("[^"]*"|'[^']*'|[^'">])*>/, '')
        @finance_output_data << output 
      end
    }
    if @response["Response"]["status"] == "FAILURE"
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "LINCOLN"
      @logger.info "No finance data found for #{@zipcode}" 
      @finance_output_data << output 
      return OpFormat.convert_to_json(@finance_output_data , "finance_data")
    end
  end
  
  def get_standard_headers
    @config["headers"].join(" ").gsub(/###REF_URL###/, @domain)
  end 
end



