require 'nokogiri'
require 'ap'
require 'net/http'
require "capybara/dsl"
require 'capybara/poltergeist'
require 'uri'
require 'open-uri'
require 'yaml'
require 'time'
require_relative "../../../lib/extracters/base/base_extractor"
require_relative "../../../lib/utils/http_get.rb"
require_relative "../../../lib/utils/utils.rb"
require_relative "../../../lib/utils/wait.rb"
require_relative "../../../lib/utils/capybara_init"
require_relative "op_format.rb"

class Extractor < BaseExtractor
  include Capybara::DSL
  include WaitModule
  def initialize(make, zipcode)
    super(make, zipcode)
    proxy_pref = "shader"
    basic_proxies = YAML.load_file("./lib/utils/proxies.yml")
    CapybaraInit.setup_browser(basic_proxies[proxy_pref].sample, @logger)
  end
  
  def load_target_page()
    @target_url = @config["target_page"].gsub("###zipcode###",@zipcode.to_s)
    @logger.info "Loading page #{@target_url}"
    UtilsModule.logger(@logger)
    WaitModule.logger(@logger)
    @response = nil
    if(UtilsModule::visit_link(@target_url))
      begin
        if (WaitModule::wait_for_xpath("//input[@class='js-locationInput']","input zipcode textbox to load", 40))
          page.all(:css, 'input.js-locationInput').first.set("#{@zipcode.to_s}") 
          page.all(:css, 'input.js-submitLocationChange').first.trigger("click")
          if (WaitModule::wait_for_xpath("//p[@class='offerLegal']","website response", 40))
            @logger.debug "Loaded site successfully with #{@zipcode}"
            @response = Nokogiri::HTML(page.html)
          else
            raise "Failed to load site with submit button"
          end
        else  
          raise "Input textbox to enter zipcode not found in loaded html"
        end
      rescue Exception => ex
        @logger.debug ex.inspect
        scraped_zipcode = Nokogiri::HTML(page.html).xpath("//a[@class='zipCode js-locationChange']")[0].text rescue nil
        @response = scraped_zipcode==@zipcode? Nokogiri::HTML(page.html) : nil
      end
    else
      @logger.debug "Failed to load site in capybara-phantom js"
    end
    delete_cookies
  end
  
  def set_zip_code()
    
  end
  
  def extract_data()
    lease_output_data = []
    if(@response.nil?)
      output = OpFormat.new  
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "Volkswagen"
      @logger.info "No lease data found for #{@zipcode}" 
      lease_output_data << output 
      return OpFormat.convert_to_json(lease_output_data)
    end
    @response.xpath("//div[@data-type='LEASE']").each do |_offer|
      output = OpFormat.new                   #creating instance of OpFormat
      output.zip = @zipcode                   #Populating instance with scraped data
      output.brand = "Volkswagen"
      output.emi = _offer.xpath(".//h2[@class='offerTitle']").text.strip.scan(/\d+/)[0] rescue nil
      output.emi_months = _offer.xpath(".//h2[@class='offerTitle']").text.strip.scan(/\d+/)[1] rescue nil
      output.down_payment = _offer.xpath(".//p[@class='offerSubtitle']").text.gsub(/\D+/,"") rescue nil
      output.offer_end_date = _offer.xpath(".//span[@class='offerEndDate']").text.strip rescue nil
      output.title1 = _offer.xpath(".//p[contains(@class,'offerType-lease')]").text rescue nil
      output.title2 = "Lease" rescue nil
      output.offer1 = _offer.xpath(".//h2[@class='offerTitle']").text.strip rescue nil
      output.offer2 = _offer.xpath(".//p[@class='offerSubtitle']").text.strip rescue nil
      output.offer3 = _offer.xpath(".//p[@class='offerExclusions']").text.strip rescue nil
      output.offer4 = _offer.xpath(".//p[@class='offerCopy']").text.strip rescue nil
      output.disclaimer1 = _offer.xpath(".//p[@class='offerLegal']").text.strip rescue nil
      lease_output_data << output  
    end
    delete_cookies
    @logger.info "Total #{lease_output_data.size} records found for #{@zipcode}" 
    return OpFormat.convert_to_json(lease_output_data) 
  end
  
  def get_standard_headers
    @config["headers"].join(" ")
  end 
  
  def delete_cookies()
    Capybara.current_session.driver.browser.clear_cookies
    Capybara.current_session.driver.browser.clear_memory_cache
    Capybara.reset_sessions!
    page.driver.clear_memory_cache
    #page.driver.quit
    `rm /tmp/c1.cookie`
  end
end



