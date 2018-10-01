module WaitModule
  @@total_wait = 0
  
  def self.logger(logger)
    @logger = logger
  end
  
  def self.default_wait_secs
    (@DEF['DEFAULT_WAIT'] rescue nil) || Capybara.default_max_wait_time
  end
  
  #returns = true/false
  def self.wait_for_page_resources(page_type = nil, timeout = self.default_wait_secs)
    sleep 0.25
    conditional_wait("all resources on #{page_type} page load completely", timeout, [Capybara.current_session]) {|_page|
      JSON.parse(_page.driver.network_traffic.to_json).all?{|n| n['response_parts'].size > 0}
    } 
  end
  
  #returns = true/false
  def self.wait_for_ajax
    wait_for_page_resources(nil, self.default_wait_secs)
  end
  
  #returns = true/false
  def self.wait_for_xpath(xpath, msg = nil, delay = self.default_wait_secs)
    conditional_wait(msg, delay, [Capybara.current_session, xpath]) {|_page, _xpath|
      _page.all(:xpath, _xpath).first != nil
    }
  end
  
  #returns = true/false
  def self.scoped_wait_for_xpath(scope, xpath, msg, delay = self.default_wait_secs)
    conditional_wait(msg, delay, [scope, xpath]) {|_scope, _xpath|
      _scope.has_xpath?(_xpath)
    }
  end
  
  #returns = true/false
  def self.conditional_wait(msg, timeout, block_args)
    @logger.info "wait for #{msg}"
    success = false
    start = Time.now.to_f
     
    Timeout.timeout(timeout) do
      wait_counter = ""
      while true
        sleep 0.25
        wait_counter << "."
        stop_flag = yield(*block_args)
        if stop_flag
          @logger.info "wait over (#{(Time.now.to_f - start).round(3)} seconds)"
          success = true
          break
        end
        if wait_counter.size > 10
          @logger.debug "waiting #{wait_counter}"
          wait_counter = ""
        end
      end
    end
    
    @@total_wait += (Time.now.to_f - start)
    return success
  rescue Timeout::Error => ex
    @logger.error "TIMEOUT expection in conditional_wait"
    return false
  end
  
  def self.wait_till_items_load(items_selector)
    attempts = 0
    while true do
      items_count = Capybara.current_session.all(items_selector, :visible => false).size
      sleep 1
      current_items_count = Capybara.current_session.all(items_selector, :visible => false).size
      @logger.debug "items_count = #{items_count} <> current_items_count = #{current_items_count} | Attempts - #{attempts}"
      break if items_count != 0 && items_count == current_items_count || attempts > 10
      attempts += 1
    end
  end
end
