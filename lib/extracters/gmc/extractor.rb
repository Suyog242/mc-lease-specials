require_relative "../../../lib/extracters/base/base_extractor"
require_relative "../../../lib/utils/http_get"
require_relative "op_format.rb"
require "pry"
require "awesome_print"
require 'logging'
require 'logger'
require 'nokogiri'
require 'date'
class Extractor < BaseExtractor
  
  def initialize(make, zip)
    super(make, zip)
    @http_get = HttpGet.new(%w[shader shader shader squid squid shader], nil, {shuffle_prefs: true}, @logger)
  end
  
  def load_target_page()
    begin
      target_url = @config["target_page"].gsub(/##ZIPCODE##/,@zipcode) #+ @zipcode.to_s
      @logger.debug "Starting lease specials extraction for zip #{@zipcode} with effective url #{target_url}"
      @response = @http_get.get(target_url, {json_res: true,curl_opts: [get_standard_headers]})
    rescue Exception => e
      @logger.error "Error ocurred while loading target page"
      @logger.error e
    end
  end
  
  def set_zip_code()
    return nil
  end
  
  def extract_lease_data()
    lease_output_data = []
    if(@response.nil?)
      output = OpFormat.new  
      output.zip = @zipcode                  
      output.brand = "GMC"
      @logger.error "No lease data found for #{@zipcode}" 
      lease_output_data << output 
      return OpFormat.convert_to_json(lease_output_data, 'lease_data')
    end
    
    @response["results"].each{|offers|
#        break
      next if offers["offerType"] != "Lease"
        begin
        output = OpFormat.new
        output.zip = @zipcode 
        output.brand = "GMC"
        output.offer_type = "Lease"
        output.title1 = offers["modelYear"] + " " + offers["displayName"].upcase
        output.title2 = offers["offerText"]["title"]["text"]
        output.title3 = "LEASE"
        offers_list = offers["offerText"]["body"]["text"].split("  ")
        offers_list.delete("") if offers_list.include? ""
        output.title4=strip_special_chars(offers_list[0]).strip rescue nil
        output.offer1=strip_special_chars(offers_list[1]).strip rescue nil
        output.offer2=strip_special_chars(offers_list[2]).gsub(/\<\w+\>|\<\/\w+\>/,'').strip + strip_special_chars(offers_list[3]).gsub(/\<\w+\>|\<\/\w+\>/,'').strip rescue nil
        output.offer3=(strip_special_chars(offers_list[4]) + strip_special_chars(offers_list[5]) + strip_special_chars(offers_list[6])).gsub(/\<\w+\>|\<\/\w+\>|\s{2,}/,'').strip rescue nil
        output.offer4 = (strip_special_chars(offers_list[7]) + strip_special_chars(offers_list.last)).strip.gsub(/\s{2,}/,"") rescue nil
        
        output.mileage_charge = strip_special_chars(offers_list.last).strip.gsub(" at participating dealers.",".") rescue ""
        
        disclaimers = offers["offerText"]["footer"]["text"].split("<br/>")
        disclaimers.delete("") if disclaimers.include? ""
        output.disclaimer1 = strip_special_chars(disclaimers[0]).gsub(/\<\w+\>|\<\/\w+\|\s{2,}>/,'').strip rescue ""
        output.disclaimer2 = strip_special_chars(disclaimers[1]).gsub(/\<\w+\>|\<\/\w+\|\s{2,}>/,'').strip rescue nil
        output.disposition_fee = output.disclaimer1.scan(/disposition fee of\s(\$\d+)/).flatten[0] rescue nil
        output.offer_end_date = Date.strptime(output.disclaimer1.scan(/Take delivery by ([\d\-]+)/).flatten[0], "%m-%d-%Y").to_s rescue nil
        output.msrp = output.disclaimer1.scan(/MSRP of \$([\d\.\,]+)/).flatten[0].gsub(/[^\d^\.]/, '').to_f rescue nil
        output.emi_months = output.offer1.match(/(\d+) months/)[1] rescue nil
        output.emi = output.offer1.match(/(\$\d+)\/month/)[1] rescue ""
        total_at_signing = output.offer2.scan(/[\d\.\,]+/).select{|x| x.match(/\d/)}
        output.down_payment = total_at_signing[0].gsub(/[^\d^\.]/, '').to_f
        output.due_at_signing = total_at_signing[0].gsub(/[^\d^\.]/, '').to_f
        if(total_at_signing.size == 2) 
          output.security_deposit = total_at_signing[1].to_i
        elsif(output.offer4.scan(/\$(\d+)\ssecurity deposit/).flatten.size>0)
          output.security_deposit = output.offer4.scan(/\$(\d+)\ssecurity deposit/).flatten[0].to_i
        end
        output.tax_registration_exclusion = output.offer4.include?("Tax, title, license, and dealer fees extra") ? "Y" : nil rescue nil
        rescue Exception => e
        @logger.debug "Error to grab listings- #{e.message} - #{e.backtrace.join("\n")}"
        @logger.error "Error in  Fetching data for zipcode = #{@zipcode}"
      end
       lease_output_data << output
    }
    @logger.debug "Total number of lease specials offer found are #{lease_output_data.size}"
    return OpFormat.convert_to_json(lease_output_data, 'lease_data')
  end
    
    
    
#    @X = @config['xpaths']

    
  
  def extract_finance_data()
    finance_output_data = []
    if(@response.nil?)
      output = OpFormat.new  
      output.zip = @zipcode                  
      output.brand = "GMC"
      @logger.error "No finance data found for #{@zipcode}" 
      finance_output_data << output 
      return OpFormat.convert_to_json(finance_output_data, 'finance_data')
    end
    @response["results"].each{|offers|
      next if offers["offerType"] == "Lease"
        begin
        output = OpFormat.new
        output.zip = @zipcode 
        output.brand = "GMC"
        if offers["offerType"] == "Finance"
          output.offer_type = "Finance" if offers["offerType"] == "Finance"
        else 
          output.offer_type = "Other" if offers["offerType"] == "Cash"
        end
        output.title1 = offers["modelYear"] +" "+offers["displayName"].upcase
        output.title2 = offers["offerText"]["title"]["text"]
        output.title3 = offers["offerType"].upcase
#        binding.pry if output.title1 == "2017 SAVANA CUTAWAY 3500"
        offers_list = offers["offerText"]["body"]["text"].split("<br/>")
        offers_list.delete("") if offers_list.include? ""
#        offers_list.delete(" Plus") if offers_list.include? " Plus"
        if offers_list.include? " Plus"
          index = offers_list.index(" Plus")
          offers_list[index+1]= "plus"+"#{offers_list[index+1]}"
          offers_list.delete(" Plus")
        end
        output.offer1=strip_special_chars(offers_list[0]).strip
        output.offer2=strip_special_chars(offers_list[1]).strip rescue nil
        output.offer3=strip_special_chars(offers_list[2]).strip rescue nil
        output.offer4 = strip_special_chars(offers_list[3]).strip if offers_list.size == 4 rescue nil
        output.offer5 = strip_special_chars(offers_list[4]).strip if offers_list.size == 5 rescue nil
        disclaimers = offers["offerText"]["footer"]["text"].split("<br/>")
        disclaimers.delete("") if disclaimers.include? ""
        output.disclaimer1 = strip_special_chars(disclaimers[0]).strip + strip_special_chars(disclaimers[1]).strip
#        output.disclaimer2 = strip_special_chars(disclaimers[1]).gsub(/\<\w+\>|\<\/\w+\|\s{2,}>/,'').strip
#        output.disposition_fee = output.disclaimer1.scan(/disposition fee of\s(\$\d+)/).flatten[0]
        output.offer_end_date = Date.strptime(output.disclaimer1.scan(/Take delivery by ([\d\-]+)/).flatten[0],"%m-%d-%Y").to_s rescue ""
        output.emi_months = output.offer1.match(/(\d+) months/)[1] rescue nil
        output.apr_rate = output.offer1.match(/([\d\.]+%) APR/)[1] rescue nil
        if output.offer_type == "Other"
          output.cashback_amount = output.offer1[/[\d\.\,]+/] rescue nil
        end
        rescue Exception => e
        @logger.debug "Error to grab listings- #{e.message} - #{e.backtrace.join("\n")}"
        @logger.error "Error in  Fetching data for zipcode = #{@zipcode}"
      end
       finance_output_data << output
    }
    @logger.debug "Total number of lease specials offer found are #{finance_output_data.size}"
    return OpFormat.convert_to_json(finance_output_data, 'finance_data')
  end
  
  
  
  def strip_special_chars(text)
      return nil if !text
      clean_text = ""
      text.each_byte { |x|  clean_text << x unless x > 127   }
      clean_text.gsub(/\[1\]/,"").gsub(/\n/,"")
      return clean_text
    end
  
  
  def get_standard_headers
   @config["headers"].join(" ")
  end
end