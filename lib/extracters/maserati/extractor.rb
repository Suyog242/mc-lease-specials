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
    Capybara.default_selector = :xpath
  end
  
  def load_target_page()
    model_url = @config["models_page"]
    @logger.info "Loading page #{model_url}"
    UtilsModule.logger(@logger)
    WaitModule.logger(@logger)
    UtilsModule::visit_link(model_url)
    if(UtilsModule::visit_link(model_url))
      begin
        if (WaitModule::wait_for_xpath(".//a[contains(text(), 'Dealer Locator')]","website response", 40))
          page.find(:xpath,".//a[contains(text(), 'Dealer Locator')]", class:"standard").click
          page.find(:xpath,".//input[@id = 'input-address']", id: 'input-address').set("#{@zipcode.to_s}")
          @logger.debug "Loaded site successfully to get dealers for #{@zipcode} zipcode"
          page.find(:xpath,".//div[@class = 'row']//img[@class = 'search']", class:"search").click
        else
          raise "Failed to load site with submit button"
        end
      rescue Exception => ex
        @logger.debug ex.inspect
        scraped_zipcode = Nokogiri::HTML(page.html).xpath("//a[@class='zipCode js-locationChange']")[0].text rescue nil
        @response = scraped_zipcode==@zipcode? Nokogiri::HTML(page.html) : nil
        delete_cookies
      end
    end
  end
end