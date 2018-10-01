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
      target_url = @config["target_page"] + @zipcode.to_s
      @logger.debug "Starting lease specials extraction for zip #{@zipcode} with effective url #{target_url}"
      @response = Nokogiri::HTML(@http_get.get(target_url, {curl_opts: [get_standard_headers]}))
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
    if(@response.nil? || @response.text.include?("We apologize, but there are no Current Offers available at this time"))
      output = OpFormat.new  
      output.zip = @zipcode                  
      output.brand = "CHEVROLET"
      @logger.error "No lease data found for #{@zipcode}" 
      lease_output_data << output 
      return OpFormat.convert_to_json(lease_output_data, 'lease_data')
    end
    @X = @config['xpaths']
    begin
      models = @response.xpath("#{@X['models']}")
    rescue Exception => ex
      @logger.error "Error no lease data found"
    end
    @logger.debug "Number of models found with lease specials program are #{models.size}"
    models.each do |model|
      begin
        output = OpFormat.new
        output.zip = @zipcode 
        output.brand = "CHEVROLET"
        output.offer_type = @X["LEASE"]
        output.title1 = model.xpath(".#{@X['title1']}")[0].text.strip
        output.title2 = model.xpath(".#{@X['title2']}").text.strip
        output.title3 = model.xpath(".#{@X['title3']}").text.strip
        output.title4 = model.xpath(".#{@X['title4']}")[1].text.strip
        output.offer1 = model.xpath(".#{@X['offer1_part1']}").text.strip + " " + model.xpath(".#{@X['offer1_part2']}").text.strip
        offer_figures = output.offer1.scan(/[\d\.\,]+/).select{|x| x.match(/\d/)}
        output.emi = offer_figures[0].gsub(/[^\d^\.]/, '').to_f rescue nil
        output.emi_months = offer_figures[1].to_i
        if(model.xpath(".#{@X['extra_offer_check']}").size == 2)
          output.offer2 = model.xpath(".#{@X['offer2']}")[2].inner_html.split("<br>")[0].strip
          output.offer3 = ""
          output.offer4 = model.xpath(".#{@X['offer2']}")[2].inner_html.split("<br>")[2].strip+model.xpath(".#{@X['offer2']}")[2].inner_html.split("<br>")[3].strip
          output.disclaimer1 = model.xpath(".#{@X['disclaimer_part1']}").text.strip + model.xpath(".#{@X['disclaimer_part2']}").text.strip
        else
          output.offer2 = model.xpath(".#{@X['offer2_3']}")[0].text.strip + model.xpath(".#{@X['offer2']}")[2].inner_html.split("<br>").reject{|x| x.empty?}.join(" ").strip.gsub(/\s+/," ") rescue ""
          output.offer3 = model.xpath(".#{@X['offer2_3']}")[1].text.strip + model.xpath(".#{@X['offer2']}")[3].inner_html.split("<br>").reject{|x| x.empty?}.join(" ").strip.gsub(/\s+/," ") rescue ""
          output.offer4 = model.xpath(".#{@X['offer2']}")[4].inner_html.split("<br>").reject{|x| x.empty?}.join(" ").strip.gsub(/\s+/," ") rescue ""
          output.disclaimer1 = model.xpath(".#{@X['disclaimer_part1']}")[0].text.strip + model.xpath(".#{@X['disclaimer_part2']}")[0].text.strip
          output.disclaimer2 = model.xpath(".#{@X['disclaimer_part1']}")[1].text.strip + model.xpath(".#{@X['disclaimer_part2']}")[1].text.strip rescue nil
        end
        total_at_signing = output.offer2.scan(/[\d\.\,]+/).select{|x| x.match(/\d/)}
        output.down_payment = total_at_signing[0].gsub(/[^\d^\.]/, '').to_f rescue nil
        output.due_at_signing = total_at_signing[0].gsub(/[^\d^\.]/, '').to_f rescue nil
        if(total_at_signing.size == 2) 
          output.security_deposit = total_at_signing[1].to_i rescue nil
        elsif(output.offer4.scan(/\$(\d+)\ssecurity deposit/).flatten.size>0)
          output.security_deposit = output.offer4.scan(/\$(\d+)\ssecurity deposit/).flatten[0].to_i rescue nil
        end
#        output.due_at_signing = output.offer2.match(/(\$[\d\,]+) due at signing/)[1]
        output.mileage_charge = output.offer4.match(/(\$[\d\.]+\/mile.*?miles)/)[1] rescue nil
        output.disposition_fee = output.disclaimer1.scan(/disposition fee of\s(\$\d+)/).flatten[0] rescue nil
#        output.mileage_charge = output.offer4.scan(/\$\d+.\d+\/mile over \d+.\d+ miles/)[0] rescue nil
        output.offer_end_date = Date.strptime(output.disclaimer1.scan(/Take delivery by ([\d\-]+)/).flatten[0], "%m-%d-%Y").to_s rescue nil
        output.msrp = output.disclaimer1.scan(/MSRP of \$([\d\.\,]+)/).flatten[0].gsub(/[^\d^\.]/, '').to_f rescue nil
        output.tax_registration_exclusion = output.offer4.include?("Tax, title, license, and dealer fees extra") ? "Y" : nil rescue nil
        rescue Exception => e
        @logger.debug "Error to grab listings- #{e.message} - #{e.backtrace.join("\n")}"
        @logger.error "Error in  Fetching data for zipcode = #{@zipcode}"
      end
        lease_output_data << output
    end
    @logger.debug "Total number of lease specials offer found are #{lease_output_data.size}"
    return OpFormat.convert_to_json(lease_output_data, 'lease_data')
  end
  
  def extract_finance_data()
    finance_output_data = []
    if(@response.nil? || @response.text.include?("We apologize, but there are no Current Offers available at this time"))
      output = OpFormat.new  
      output.zip = @zipcode                  
      output.brand = "CHEVROLET"
      @logger.error "No finance data found for #{@zipcode}" 
      finance_output_data << output 
      return OpFormat.convert_to_json(finance_output_data, 'finance_data')
    end
    @X = @config['finance_xpaths']
    begin
      models = @response.xpath("#{@X['models']}")
    rescue Exception => ex
      @logger.error "Error no finance data found"
    end
    @logger.debug "Number of models found with finance offers program are #{models.size}"
    models.each do |model|
      begin
        output = OpFormat.new
        output.zip = @zipcode 
        output.brand = "CHEVROLET"
        output.offer_type = @X["FINANCE"]
        output.title1 = model.xpath(".#{@X['title1']}")[0].text.strip
        output.title2 = model.xpath(".#{@X['title2']}").text.strip
        output.title3 = model.xpath(".#{@X['title3']}").inner_html.split('<br>')[0].strip rescue nil
#        binding.pry if output.title1 == '2018 CHEVROLET Malibu excludes L'
        if model.xpath(".#{@X['offer1_part1']}").size == 2
         output.offer1 = model.xpath(".#{@X['offer1_part1']}")[0].text.strip + " " + model.xpath(".#{@X['offer1_part2']}")[0].text.strip
         output.offer2 = model.xpath(".#{@X['offer1_part1']}")[1].text.strip + " " + model.xpath(".#{@X['offer1_part2']}")[2].text.strip rescue nil
         output.offer3 = model.xpath(".#{@X['offer2']}").inner_html.split('<br>')[1].strip rescue nil
         output.offer_end_date = Date.strptime(output.offer3.scan(/Take delivery by ([\d\-]+)/).flatten[0], "%m-%d-%Y").to_s rescue ""
        else 
        output.offer1 = model.xpath(".#{@X['offer1_part1']}").text.strip + " " + model.xpath(".#{@X['offer1_part2']}").text.strip
        output.offer2 = model.xpath(".#{@X['offer2']}").inner_html.split('<br>')[1].strip rescue nil
        output.offer_end_date = Date.strptime(output.offer2.scan(/Take delivery by ([\d\-]+)/).flatten[0], "%m-%d-%Y").to_s rescue ""
        end
        output.apr_rate = output.offer1.scan(/([\d\.\,]+)/).flatten[0] rescue nil
        output.emi_months = output.offer1.scan(/([\d\.\,]+)/).flatten[1] rescue nil
        rescue Exception => e
        @logger.debug "Error to grab listings- #{e.message} - #{e.backtrace.join("\n")}"
        @logger.error "Error in  Fetching data for zipcode = #{@zipcode}"
        end
        finance_output_data << output
    end
    @logger.debug "Total number of finance offer found are #{finance_output_data.size}"
    other_offer_check(finance_output_data) 
    
    return OpFormat.convert_to_json(finance_output_data, 'finance_data')
  end
  
  def other_offer_check(finance_output_data)
    
    @X = @config['other_offers_xpaths']
    begin
      models = @response.xpath("#{@X['models']}")
    rescue Exception => ex
      @logger.error "Error no finance data found"
    end
    @logger.debug "Number of models found with finance offers program are #{models.size}"
    models.each do |model|
      begin
        output = OpFormat.new
        output.zip = @zipcode 
        output.brand = "CHEVROLET"
        output.offer_type = @X["OTHEROFFERS"]
        output.title1 = model.xpath(".#{@X['title1']}")[0].text.strip rescue nil
        output.title2 = model.xpath(".#{@X['title2']}").text.strip rescue nil
        output.title3 = model.xpath(".#{@X['title3']}").inner_html.split('<br>')[0].strip rescue nil
#        binding.pry if output.title1 == '2018 CHEVROLET Malibu excludes L'
        if(model.xpath(".#{@X['extra_offer_check']}").size == 2)
          output.offer1 = model.xpath(".#{@X['title1']}")[1].inner_html.split("<br>")[0].strip rescue nil
          output.offer2 = model.xpath(".#{@X['title1']}")[2].inner_html.split("<br>")[0].strip rescue nil
          output.offer3 = model.xpath(".#{@X['offer1_part1']}")[0].text.strip + " " + model.xpath(".#{@X['offer1_part2']}")[0].text.strip rescue nil
          output.disclaimer1 = model.xpath(".#{@X['offer2']}").inner_html.split('<br>')[1].strip rescue nil
        else
          output.offer1 = model.xpath(".#{@X['offer1_part1']}")[0].text.strip + " " + model.xpath(".#{@X['offer1_part2']}")[0].text.strip rescue nil
          output.disclaimer1 = model.xpath(".#{@X['offer2']}").inner_html.split('<br>')[1].strip rescue ""
        end
        output.cashback_amount = output.offer1[/[\d\.\,]+/] rescue nil
        output.offer_end_date = Date.strptime(output.disclaimer1.scan(/Take delivery by ([\d\-]+)/).flatten[0], "%m-%d-%Y").to_s rescue nil
        rescue Exception => e
        @logger.debug "Error to grab listings- #{e.message} - #{e.backtrace.join("\n")}"
        @logger.error "Error in  Fetching data for zipcode = #{@zipcode}"
      end
        finance_output_data << output
    end
    @logger.debug "Total number of ohter offers found are #{finance_output_data.size}"
   
  end
  
  def get_standard_headers
   @config["headers"].join(" ")
  end
end