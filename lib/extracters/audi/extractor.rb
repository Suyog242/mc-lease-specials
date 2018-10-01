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
      target_url = @config["target_page"].gsub(/###ZIP###/,@zipcode.to_s)
      @logger.debug "Getting nearby dealer for zip #{@zipcode}"
      response = @http_get.get(target_url, {json_res: true, curl_opts: [get_standard_headers]})
      @dealer_details = response["payload"][0]
      @dealer_details["dealerUrls"].each do |url|
        if url["urlTypeCode"] == "PRIURL"
          @dealer_site = url["url"]
        end
      end
      @logger.debug "Found nearest dealer at zip #{@dealer_details['zip']} with domain "+ @dealer_site
      target_url = @config["dealer_srp_url"].gsub(/###dealer_domain###/,@dealer_site.to_s)
      @logger.debug "Retriving all models and their respective lease details page url's"
      @lease_vdp_url = Queue.new
      @other_offers_url = Queue.new
      (@http_get.get(target_url, {json_res: true, curl_opts: [get_standard_headers]}))["trims"].each do |model|
        model["incentiveTypes"].include?("LEASE") ? @lease_vdp_url.push(@dealer_site + model["detailsHref"]) : @other_offers_url.push(@dealer_site + model["detailsHref"])
      end
      @logger.debug "Found #{@lease_vdp_url.size} models with lease specials programs"
    rescue Exception => e
      @logger.error "Error while fetching target urls!"
      @logger.error "#{e} ==== #{e.backtrace}"
    end
  end
  
  def set_zip_code()
    return nil
  end
  
  def extract_lease_data()
    lease_output_data = []
    if(@lease_vdp_url.empty?)
      output = OpFormat.new  
      output.zip = @zipcode                  
      output.brand = "AUDI"
      @logger.error "No lease data found for #{@zipcode}" 
      lease_output_data << output 
      return OpFormat.convert_to_json(lease_output_data)
    end
    @X = @config['xpaths']
    parallel = @lease_vdp_url.size > 10 ? 10 : (@lease_vdp_url.size-1 <= 0 ? 1 : @lease_vdp_url.size-1 )
    @logger.debug "Starting extraction of each lease specials offer with #{parallel} number of threads"
    workers = (0...parallel).map do |thread_id|
      Thread.new do
        begin
          while url = @lease_vdp_url.pop(true)
            model = Nokogiri::HTML(@http_get.get(url, {curl_opts: [get_standard_headers]}))
            trims = model.xpath("#{@X['trim_offers']}")
            @logger.debug "Number of lease specials offers found \a #{url} is #{trims.size}"
            trims.each do |trim|
              output = OpFormat.new
              output.zip = @zipcode
              output.effective_zip = @dealer_details["zip"]
              output.dist_between_two_zip = @dealer_details["distance"]
              output.title1 = model.xpath("#{@X['title1']}").text.strip
              output.title2 = trim.xpath(".#{@X['title2']}").text.strip
              output.title3 = trim.xpath(".#{@X['title3']}").text.strip
              output.brand = "AUDI"
              output.offer1 = trim.xpath(".#{@X['offer1']}").text.strip
              output.offer2 = trim.xpath(".#{@X['offer2']}").text.strip
              output.offer3 = trim.xpath(".#{@X['offer3']}").text.strip
              output.offer4 = trim.xpath(".#{@X['offer4']}").text.strip
              output.offer_type = "Lease"
              output.disclaimer1 = trim.xpath(".#{@X['disclaimer']}").text.strip
              offer_figures = output.offer1.scan(/[\d\.\,]+/).select{|x| x.match(/\d/)}
              output.emi = offer_figures[0].gsub(/[^\d^\.]/, '').to_f rescue ""
              output.emi_months = offer_figures[1].to_i
              output.mileage_charge = output.disclaimer1.match(/(\$[\d\.]+\/mile.*?use.)/)[1] rescue nil
              output.down_payment = output.offer2.scan(/[\d\.\,]+/).select{|x| x.match(/\d/)}[0].gsub(/[^\d^\.]/, '').to_f rescue nil
              output.due_at_signing = output.offer2.scan(/[\d\.\,]+/).select{|x| x.match(/\d/)}[0].gsub(/[^\d^\.]/, '').to_f rescue nil
              offer_dates = output.offer3.scan(/[\d\/]+/).flatten rescue ""
              output.offer_start_date = Date.strptime(offer_dates[0], "%m/%d/%Y").to_s rescue nil
              output.offer_end_date = Date.strptime(offer_dates[1], "%m/%d/%Y").to_s rescue nil
              output.msrp = output.disclaimer1.scan(/MSRP of \$([\d\,\.]+)/).flatten[0].gsub(/[^\d^\.]/, '').to_f rescue nil
              output.acquisition_fee = output.disclaimer1.scan(/acquisition fee of \$([\d\,\.]+)/).flatten[0].gsub(/[^\d^\.]/, '').to_f rescue nil
              output.disposition_fee = output.disclaimer1.scan(/disposition fee of \$([\d\,\.]+)/).flatten[0].gsub(/[^\d^\.]/, '').to_f rescue nil
              output.security_deposit = output.offer4.match(/(\$[\d\,]+) security deposit/)[1] rescue nil
              output.tax_registration_exclusion = (output.offer4.include?("Excludes tax, title, license, registration,") || output.disclaimer1.include?("Excludes tax, title, license, registration,") ? "Y" : nil) rescue nil
              lease_output_data << output
            end
          end
          rescue Exception => ex
            @logger.error "Error:::#{ex.message}$$$#{ex.backtrace} === For thread_id::#{thread_id}"
        end
      end
    end
    workers.map(&:join);
    @logger.debug "Total number of offers found for zip #{@zipcode} are #{lease_output_data.size}"
    return OpFormat.convert_to_json(lease_output_data, "lease_data")
  end
  
  def extract_finance_data()
    finance_output_data = []
    if(@other_offers_url.empty?)
      output = OpFormat.new  
      output.zip = @zipcode                  
      output.brand = "AUDI"
      @logger.error "No other offers data found for #{@zipcode}" 
      finance_output_data << output 
      return OpFormat.convert_to_json(finance_output_data)
    end
    @X = @config['other_offers']
    parallel = @other_offers_url.size > 10 ? 10 : (@other_offers_url.size-1 <= 0 ? 1 : @other_offers_url.size-1 )
    @logger.debug "Starting extraction of each other finance offer with #{parallel} number of threads"
    workers = (0...parallel).map do |thread_id|
      Thread.new do
        begin
          while url = @other_offers_url.pop(true)
            model = Nokogiri::HTML(@http_get.get(url, {curl_opts: [get_standard_headers]}))
            trims = model.xpath("#{@X['trim_offers']}")
            @logger.debug "Number of other finance offers found \a #{url} is #{trims.size}"
            trims.each do |trim|
              output = OpFormat.new
              output.zip = @zipcode
              output.effective_zip = @dealer_details["zip"]
              output.dist_between_two_zip = @dealer_details["distance"]
              output.title1 = model.xpath("#{@X['title1']}").text.strip
              output.title2 = trim.xpath(".#{@X['title2']}").text.strip
              output.offer1 = trim.xpath(".#{@X['title3']}").text.strip
              output.brand = "AUDI"
              output.offer_type = "Other"
#              output.offer1 = trim.xpath(".#{@X['offer1']}").text.strip
              output.offer2 = trim.xpath(".#{@X['offer2']}").text.strip
              output.offer3 = trim.xpath(".#{@X['offer3']}").text.strip
              output.offer4 = trim.xpath(".#{@X['offer4']}").text.strip
              output.disclaimer1 = trim.xpath(".#{@X['disclaimer']}").text.strip
#              offer_figures = output.offer1.scan(/[\d\.\,]+/).select{|x| x.match(/\d/)}
#              output.emi = offer_figures[0].gsub(/[^\d^\.]/, '').to_f
#              output.emi_months = offer_figures[1].to_i
#              output.down_payment = output.offer2.scan(/[\d\.\,]+/).select{|x| x.match(/\d/)}[0].gsub(/[^\d^\.]/, '').to_f
              offer_dates = output.offer3.scan(/[\d\/]+/).flatten
              output.offer_start_date = Date.strptime(offer_dates[0], "%m/%d/%Y").to_s rescue nil
              output.offer_end_date = Date.strptime(offer_dates[1], "%m/%d/%Y").to_s rescue nil
              #output.msrp = output.disclaimer1.scan(/MSRP of \$([\d\,\.]+)/).flatten[0].gsub(/[^\d^\.]/, '').to_f
              #output.aquisitionFee = output.disclaimer1.scan(/acquisition fee of \$([\d\,\.]+)/).flatten[0].gsub(/[^\d^\.]/, '').to_f
              finance_output_data << output
            end
          end
          rescue Exception => ex
            @logger.error "Error:::#{ex.message}$$$#{ex.backtrace} === For thread_id::#{thread_id}"
        end
      end
    end
    workers.map(&:join);
    @logger.debug "Total number of offers found for zip #{@zipcode} are #{finance_output_data.size}"
    return OpFormat.convert_to_json(finance_output_data,"finance_data")
  end
  
  def get_standard_headers
   @config["headers"].join(" ")
  end
end