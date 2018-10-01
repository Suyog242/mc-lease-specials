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
    @domain = URI(@config["target_page"]).host
    response = @http_get.get(@config["target_page"], {
        json_res: false, 
        curl_opts: [get_standard_headers]
      })
    if !response
      lease_output_data = []
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "FORD"
      @logger.info "Unable to load target page for #{@zipcode}" 
      lease_output_data << output 
      return OpFormat.convert_to_json(lease_output_data , "lease_data")
    end
    @noko_doc = Nokogiri::HTML(response)
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
    @cars_info_arr = []
    @noko_doc.xpath("//li[@class='vehicle-list-item']").each{ |vehicle|
      begin
        car_info = JSON.parse(vehicle["data-pricing-context"])
        @cars_info_arr << {
          model: car_info["model"],
          year: car_info["year"]
        }
        if @cars_info_arr.empty?
          lease_output_data = []
          output = OpFormat.new  
          output.zip = @zipcode                   #Populating instance with scraped data
          output.brand = "FORD"
          @logger.info "No lease data found for #{@zipcode}" 
          lease_output_data << output 
          return OpFormat.convert_to_json(lease_output_data , "lease_data")
        end
      rescue
      end
    }

    lease_output_data = []
    @cars_info_arr.each{ |_car|
      lease_url = "#{@config["lease_base_url"]}#{post_data(@make.capitalize, _car[:model], @zipcode.to_s, _car[:year])}"
      @response = @http_get.get(lease_url, {
          json_res: true, 
          curl_opts: [get_standard_headers]
        })
      if !@response
        output = OpFormat.new  
        output.zip = @zipcode                   #Populating instance with scraped data
        output.brand = "FORD"
        @logger.info "No lease data found for #{@zipcode}" 
        lease_output_data << output 
        return OpFormat.convert_to_json(lease_output_data , "lease_data")
      end      
      if @response["Response"]["status"] == "FAILURE"
        output = OpFormat.new  
        output.zip = @zipcode                   #Populating instance with scraped data
        output.brand = "FORD"
        @logger.info "No lease data found for #{@zipcode}" 
        lease_output_data << output 
        return OpFormat.convert_to_json(lease_output_data , "lease_data")
      end
                
      begin
        @offers = @response["Response"]["Nameplate"]["Groups"]
        lease_offers = if @offers.empty?
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
        output.brand = "FORD"
        output.offer_start_date = lease_offer["Campaign"]["StartDate"] rescue nil
        output.offer_end_date = lease_offer["Campaign"]["EndDate"] rescue nil
        output.security_deposit = lease_offer["Campaign"]["SecurityDeposite"] rescue nil if !lease_offer["Campaign"]["SecurityDeposite"].empty?
            
        title1, title2 = lease_offer["Campaign"]["Name"].scan(/\>(.*?)\</).select{|x| !x[0].strip.empty?}.flatten rescue [nil, nil]
        offer1, offer2 = lease_offer["Campaign"]["Detail"].scan(/\>(.*?)\</).join('').split(/(?<=mos)\./) rescue [nil, nil]
                    
        output.title1 = title1.gsub(/&amp;/, '&').strip rescue nil
        output.title2 = title2.gsub(/&amp;/, '&').strip rescue nil
        output.offer1 = offer1.strip rescue nil
        output.offer2 = offer2.strip rescue nil
        output.disclaimer1 = OpFormat.parse_text(lease_offer["Campaign"]["Disclaimer"]).gsub(/<("[^"]*"|'[^']*'|[^'">])*>/, '') rescue nil
        output.offer_type = "Lease"
        output.disposition_fee = lease_offer["Campaign"]["Disclaimer"].scan(/\$\d+ lease disposition .*vehicle\. /).first rescue nil
        output.mileage_charge = lease_offer["Campaign"]["Disclaimer"].scan(/.Lessee.*\mile./).first.strip rescue nil
        output.due_at_signing = lease_offer["Campaign"]["CashDueAtSigning"] rescue nil
        output.emi = lease_offer["Campaign"]["Payment"] rescue nil
        output.emi_months = lease_offer["Campaign"]["Term"] rescue nil
        output.model_details = @response["Response"]["Nameplate"]["model"] rescue nil
        output.tax_registration_exclusion = lease_offer["Campaign"]["Disclaimer"].scan(/Tax.*extra./).empty? ? "Y" : "N" rescue nil
        output.cashback_amount =  lease_offer["Campaign"]["Disclaimer"].scan(/\$.*cash back|\$.* Customer Cash/i).first.gsub(/(\d+) (.*)/,'\1').strip
                    
        lease_offer_for_modal << output
        #        ap lease_offer_for_modal
      }  
      lease_output_data << lease_offer_for_modal if !lease_offer_for_modal.empty?
      #      ap lease_output_data
    }
    lease_output_data.flatten!
    OpFormat.convert_to_json(lease_output_data , 'lease_data')   #Converting array of output objects in to json format
    #    }
  end
  def  extract_finance_data
    finance_output_data = []
    if @cars_info_arr.empty?
      finance_output_data = []
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "FORD"
      @logger.info "No finance data found for #{@zipcode}" 
      finance_output_data << output 
      return OpFormat.convert_to_json(finance_output_data , "finance_data")
    end
    @cars_info_arr.each_with_index{ |_car , index|
      lease_url = "#{@config["lease_base_url"]}#{post_data(@make.capitalize, _car[:model], @zipcode.to_s, _car[:year])}"
      @response = @http_get.get(lease_url, {
          json_res: true, 
          curl_opts: [get_standard_headers]
        })
      @offers = @response["Response"]["Nameplate"]["Groups"] rescue nil
      trim_offer =  @response["Response"]["Nameplate"]["Trims"]["Trim"] rescue nil
      if @offers == "" && trim_offer && !trim_offer.is_a?(Hash)
        trim_offer.each{|main_offer|
          @offers = main_offer["Groups"] rescue nil
          next if  @offers == "" || @offers["Group"].is_a?(Hash)
          finance_output_data =  scrape_finance_data(@offers , lease_url , finance_output_data)
        }
      else
        next if @offers == ""
        finance_output_data = scrape_finance_data(@offers , lease_url , finance_output_data)
      end
    }
    finance_output_data.flatten if !finance_output_data.empty? 
    OpFormat.convert_to_json(finance_output_data , 'finance_data')   #Converting array of output objects in to json format
  end
  def scrape_finance_data(offers , url ,finance_output_data)
    offers["Group"].each_with_index {|group , index|
      next if group.is_a?(Array)
      if group["Campaign"]
        output = OpFormat.new
        next if !group["Campaign"]["CampaignType"].include?("APR") 
        model_name = "#{group["Campaign"]["Name"]}".scan(/\>(.*?)\</).select{|x| !x[0].strip.empty?}.flatten.first rescue nil
        #        next if model_name  != "2018 Ford Edge"
        details = Nokogiri::HTML("#{group["Campaign"]["Detail"]}").text.split(/OR|\+|PLUS/) rescue nil
        if details[1]
          output = OpFormat.new
          output.brand = "FORD"
          output.title1 = "Cash offers"
          output.offer_type = "Other"
          output.apr_rate =  group["Campaign"]["APRRate"] rescue nil
          output.offer_start_date = group["Campaign"]["startDate"] rescue nil
          output.offer_end_date =  group["Campaign"]["endDate"] rescue nil
          output.cashback_amount = details[1].gsub(/Cash Back|Bonus Cash|\s+/i,'') rescue nil
          output.title2 =  model_name
          output.offer1 = details[1] rescue nil
          output.zip = @zip
          finance_output_data << output if !output.brand.nil? 
        end
        output.brand = "FORD"
        output.title1 = "Retail offers"
        output.offer_type = "Finance"
        output.apr_rate =  group["Campaign"]["APRRate"] rescue nil
        output.emi_months = group["Campaign"]["Term"] rescue nil
        output.title2 =  model_name 
        output.offer1 = details[0]
        output.offer_start_date = group["Campaign"]["StartDate"] rescue nil
        output.offer_end_date = group["Campaign"]["EndDate"] rescue nil
        output.zip = @zip
        #          output.offer2 = details[1]
        output.disclaimer1 = OpFormat.parse_text(group["Campaign"]["Disclaimer"]).gsub(/<("[^"]*"|'[^']*'|[^'">])*>/, '') rescue nil
        finance_output_data << output  if !output.brand.nil?
      end
    }
    return finance_output_data.uniq
  end
  
  def get_standard_headers
    @config["headers"].join(" ").gsub(/###REF_URL###/, @domain)
  end 
end



