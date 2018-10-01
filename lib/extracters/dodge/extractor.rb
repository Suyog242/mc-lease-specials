require 'json'
require 'ap'
require_relative "../../../lib/extracters/base/base_extractor"
require_relative "../../../lib/utils/http_get.rb"
require_relative "./op_format"
require 'uri'

class Extractor < BaseExtractor
  def initialize(make, zipcode)
    super(make, zipcode)
    @year = [Date.today.prev_year.year, Date.today.year]
    @zip = zipcode
    @http_get = HttpGet.new(%w[shader shader shader squid squid shader], nil, {shuffle_prefs: true}, @logger)
  end
  
  def load_target_page()
    @response = []
    @year.each{ |year|
      @target_url = @config["target_page"].gsub("###zipcode###", @zipcode.to_s)
      .gsub("###year###", year.to_s)
      @finance_url = "http://www.dodgecurrentoffers.com/hostd/incentives/getoffers.json?zip=#{@zipcode.to_s}&year=#{year}&divisionCode=D&modelCode="
      @domain = URI(@target_url).host
      @response << JSON.parse(@http_get.get(@target_url, {json_res: true, curl_opts: [get_standard_headers]}).to_json)
      if !@response
        lease_output_data = []
        output = OpFormat.new  
        output.zip,output.brand = @zipcode,"DODGE"                   
        @logger.info "No lease data found for #{@zipcode}" 
        return OpFormat.convert_to_json(lease_output_data << output, "lease_data")
      end
    }
  end
  
  def set_zip_code()
    
  end
  
  def extract_lease_data()
    lease_output_data = []
    @models = []
    @response.each{ |response|
      if response["result"]["result"] == "FAILURE"
        output = OpFormat.new  
        output.zip = @zipcode                   #Populating instance with scraped data
        output.brand = "DODGE"
        @logger.info "No lease data found for #{@zipcode}" 
        lease_output_data << output 
        return OpFormat.convert_to_json(lease_output_data << output, "lease_data")
      end
      response["result"]["data"]["modelYears"].each{ |model_year|
        model_year["models"].each{ |model|
          @models << model["modelCode"]
          title1 = "#{response["getAdvertisedOffersCommand"]["year"]} #{model["description"]}"
          model["offers"].each{ |offer|
            next if offer["type"].nil? || offer["type"] != "lease_promo"
            output = OpFormat.new                   #creating instance of OpFormat
            output.zip = @zipcode                   #Populating instance with scraped data
            output.brand = "DODGE"
            output.emi = "$#{offer["offerDetails"]["monthlyPayment"]}" rescue nil
            output.emi_months = offer["offerDetails"]["numberOfPayment"] rescue nil
            output.offer_start_date = offer["incentives"][0]["startDate"].gsub(/(\d+)\-(\d+)\-(\d+)/,'\3-\2-\1') rescue nil
            output.offer_end_date = offer["incentives"][0]["endDate"].gsub(/(\d+)\-(\d+)\-(\d+)/,'\3-\2-\1') rescue nil
            output.security_deposit = offer["incentives"][0]["securityDeposit"] rescue nil
            output.title1 = title1 rescue nil
            output.due_at_signing = "$#{offer["offerDetails"]["totalDueAtSigning"]}" rescue nil
            output.msrp = offer["vehicles"][0]["configuredPrice"].to_s rescue nil
            output.disposition_fee = offer["incentives"][0]["disclaimer"].match(/\$\d+ disposition/).to_s.gsub("disposition",'') rescue nil
            output.mileage_charge = offer["disclaimer"].scan(/.Lessee.*year/).first rescue nil
            output.model_details = offer["vehicles"].first["bodymodelCode"] rescue nil
            output.offer_type = "Lease"
            mixup_title_and_offer = offer["name"]
            title2 = mixup_title_and_offer.gsub(/(.*?for).*/, '\1') rescue nil
            output.title2 = title2
            
            offers = mixup_title_and_offer.split('.') rescue nil
            output.offer1 = offers[0].gsub("#{offers[0]}", title2).strip rescue nil
            output.offer2 = offers[1].strip rescue nil
            output.offer3 = offers[2].strip rescue nil
            output.tax_registration_exclusion = offer["disclaimer"].scan("Tax, title &amp; license extra")[0].empty? ? "N" : "Y" rescue nil
            output.offer5 = "Offer expires on #{offer["incentives"][0]["endDate"]}" if !offer["incentives"][0]["endDate"].nil?
            output.disclaimer1 = OpFormat.parse_text(offer["disclaimer"]).gsub(/<("[^"]*"|'[^']*'|[^'">])*>/, '') rescue nil
            lease_output_data << output            
          }
        }
      }
    }
    
    if lease_output_data.empty?
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "DODGE"
      @logger.info "No lease data found for #{@zipcode}" 
      lease_output_data << output 
    end
    
    OpFormat.convert_to_json(lease_output_data , 'lease_data')   #Converting array of output objects in to json format
  end
  
  def extract_finance_data()
    finance_output_data = []
    @models.uniq.each{|model_name|
      url = @finance_url + "#{model_name}"
      @finance_response = JSON.parse(@http_get.get(url, {json_res: true, curl_opts: [get_standard_headers]}).to_json) 
      if !@finance_response || @finance_response["result"].empty?
        output = OpFormat.new  
        output.zip = @zipcode                   #Populating instance with scraped data
        output.brand = "DODGE"
        output.offer_type = "Finance"
        @logger.info "No Finance data found for #{@zipcode}" 
        finance_output_data << output 
        return OpFormat.convert_to_json(finance_output_data << output, "finance_data")
      end
      @finance_response["result"]["data"]["offerTypes"].each{|offer_type|
        if offer_type["type"].include?("subv_apr") 
          offer_type["offers"].each{|offer|
            vehicles = offer["vehicles"]
            vehicles.each{|model|
              model_code = []
              model_code << model["ccode"]
              output = OpFormat.new 
              @title1 = "#{model["year"]} " "#{model["division"]} " "#{model["description"]}" rescue nil
              @model = model["description"].gsub(/pacifica/i,'')
              output.zip = @zipcode 
              output.brand = "DODGE"
              output.title1 = @title1
              output.title2 = @model
              output.offer_type = "Finance"
              output.model_details = model["bodymodelCode"] rescue nil
              offers = "#{offer["name"]}".split(/\+|plus/i)
              offer["incentives"].each do |incentive|
                msrp =  "#{model["configuredPrice"].to_s}" rescue nil
                next if incentive["category"] != "apr" 
                category = incentive["category"] rescue nil
                term = incentive["terms"] rescue nil
                output.apr_rate = "#{term[0]["value"]} %" rescue nil
                output.emi_months = term[0]["duration"].to_s rescue nil
                output.msrp = "$#{msrp}"  rescue nil
                output.offer_start_date = offer["startDate"].gsub(/(\d+)\-(\d+)\-(\d+)/,'\3-\2-\1') rescue nil
                output.offer1 =  "#{term[0]["value"]}% " "#{category} " "#{term[0]["duration"]} months" rescue nil
                output.offer5 = offers[0] rescue nil
                output.offer6 = offers[1] rescue nil
                output.disclaimer1 = "#{OpFormat.parse_text(offer["disclaimer"]).gsub(/<("[^"]*"|'[^']*'|[^'">])*>/, '')}" rescue nil
                finance_output_data << output
                if term.size > 1
                  term[1..term.size].each{|term_data|
                    output = OpFormat.new 
                    output.zip = @zipcode 
                    output.brand = "DODGE"
                    output.title1 = @title1
                    output.title2 = @model
                    output.apr_rate = "#{term_data["value"]} %" rescue nil
                    output.emi_months = "#{term_data["duration"].to_s}" rescue nil
                    output.offer_type = "Finance"
                    output.model_details = model["bodymodelCode"] rescue nil
                    output.msrp = "$#{msrp}" rescue nil
                    output.offer_start_date = offer["startDate"].gsub(/(\d+)\-(\d+)\-(\d+)/,'\3-\2-\1')  rescue nil
                    output.offer_end_date = offer["endDate"].gsub(/(\d+)\-(\d+)\-(\d+)/,'\3-\2-\1')  rescue nil
                    output.offer1 =  "#{term_data["value"]}% " "#{category} " "#{term_data["duration"]} months" rescue nil
                    output.offer5 = offers[0] rescue nil
                    output.offer6 = offers[1] rescue nil 
                    output.disclaimer1 = "#{OpFormat.parse_text(offer["disclaimer"]).gsub(/<("[^"]*"|'[^']*'|[^'">])*>/, '')}" rescue nil
                    finance_output_data << output
                  } 
                end
              end
            }
          }
        elsif  offer_type["type"].include?("cash")
          offer_type["offers"].each do |offer|
            offer["vehicles"].each{|model|
              output = OpFormat.new
              next if !offer_type["category"].include?("cash")
              output.brand = "DODGE"
              output.title1 =  @title1
              output.offer_type = "Other"
              output.offer_start_date = offer["startDate"].gsub(/(\d+)\-(\d+)\-(\d+)/,'\3-\2-\1') rescue nil
              output.offer_end_date = offer["endDate"].gsub(/(\d+)\-(\d+)\-(\d+)/,'\3-\2-\1') rescue nil
              output.cashback_amount = offer["offerDetails"]["amount"] rescue nil
              output.msrp = model["configuredPrice"].to_s rescue nil
              output.title2 = model["description"] rescue nil
              output.title3 = offer_type["type"] rescue nil
              output.offer1 = offer["name"] rescue nil
              output.offer2 = "Offer expires on #{offer["endDate"]}" rescue nil
              output.disclaimer1 = OpFormat.parse_text(offer["disclaimer"]).gsub(/<("[^"]*"|'[^']*'|[^'">])*>/, '') rescue nil
              output.zip = @zipcode
              finance_output_data << output
            }
          end
        end
      }
    }
    OpFormat.convert_to_json(finance_output_data , 'finance_data')   #Converting array of output objects in to json format
    if finance_output_data.empty?
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "DODGE"
      @logger.info "No finance data found for #{@zipcode}" 
      finance_output_data << output 
      return OpFormat.convert_to_json(finance_output_data, "finance_data") 
    end
  end

  def get_standard_headers
    @config["headers"].join(" ").gsub(/###REF_URL###/, @domain)
  end 
end



