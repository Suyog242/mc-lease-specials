=begin
ENV vars

PJS_DEBUG=1 will turn on phantomjs debug logs
=end
class CapybaraInit  
  def self.setup_browser(proxy_type,logger)
    @logger = logger
    ENV['BROWSER'] = "true"
    proxy_options = []
    proxy_options << "--proxy="+proxy_type.split("@").last 
    proxy_options <<  "--proxy-auth="+proxy_type.split("@").first  if proxy_type.include?('@') 
    @logger.info "PROXY -- #{proxy_options.first}"
    @logger.info "PROXY_AUTH -- #{proxy_options.last}"
    
    more_opts = []
    if ENV['PJS_DEBUG']
      more_opts << "--debug=true"
    end
    
    Capybara.run_server = false

    Capybara.register_driver :poltergeist do |app|
      Capybara::Poltergeist::Driver.new(app, {
          js_errors: false,
          phantomjs_options: [          
            "--ignore-ssl-errors=yes",
            '--ssl-protocol=any',
            "--load-images=false",
            "--web-security=false",
            "--local-to-remote-url-access=true",
            "--cookies-file=/tmp/c1.cookie",
          ]+ proxy_options + more_opts,
          :phantomjs => "/usr/local/bin/phantomjs"
          
        })
    end
    Capybara.current_driver = :poltergeist
        
    #default_wait_time - The maximum number of seconds to wait for asynchronous processes to finish (Default: 2)
    Capybara.default_max_wait_time = 120
    Capybara.default_selector = :xpath
    Capybara.current_session.driver.browser.clear_cookies 
    user_agent = File.read("./lib/utils/google_chrome_useragents").split("\n").sample
    Capybara.current_session.driver.headers = { "User-Agent" => user_agent }                                                          
  end
end
