module UtilsModule
  
  require 'geokit'
  require 'geocodio'
  #returns = true/false
  def self.logger(logger)
    @logger = logger
  end
  
  def self.mode_debug(mode)
    mode == "development"
  end

  def self.b(mode)
    binding.pry if mode_debug(mode)
  end

  def self.html(mode)
    save_and_open_page if mode_debug(mode)
  end

  def self.snap(mode)
    save_and_open_screenshot if mode_debug(mode)
  end

  def self.full_snap(path)
    save_screenshot(path, :full => true)
  end

  #returns int
  def self.to_cents(val)
    val.nil? ? 0 : (val.to_f * 100).to_i
  end

  def self.click_step
    {:action => NavStepAction::CLICK}
  end

  def self.visit_link(link, retrials = 5)
    @logger.debug "link = #{link}, retrials = #{retrials} "
    success = false
    retrials.times do |i|
      sleep 1 if i > 0
      begin
        Capybara.current_session.visit(link)
        success = true
        @logger.debug "Site loaded successfully in #{i+1} attempt"
        break
      rescue Capybara::Poltergeist::StatusFailError, 
          Capybara::Poltergeist::BrowserError,
          Capybara::Poltergeist::TimeoutError,
          Capybara::Poltergeist::DeadClient => ex
        @logger.error "Try - #{i+1} : Failed to load page - #{link} - #{print_backtrace(ex)}"
        success = false
        Capybara.current_session.reset!
      end    
    end
    
    success
  end
  
  def self.get_first_visible_element(context, xpath, msg = nil)
    visible = true
    elem = context.first(xpath)
    if !elem
      visible = false
      elem = context.first(xpath, :visible => false)
    end
    @logger.debug %Q[#{msg} - visible: #{visible} -  xpath = `#{xpath}` - #{elem.inspect}]
    elem
  end
  
  def self.get_first_visible_element(context, xpath, msg = nil)
    visible = true
    elem = context.first(xpath)
    @logger.debug %Q[#{msg} - visible: #{visible} -  xpath = `#{xpath}` - #{elem.inspect}]
    elem
  end
  
  def self.get_first_element(context, xpath, msg = nil)
    visible = true
    elem = context.first(xpath)
    if !elem
      visible = false
      elem = context.first(xpath, :visible => false)
    end
    @logger.debug %Q[#{msg} - visible: #{visible} -  xpath = `#{xpath}` - #{elem.inspect}]
    elem
  end

  def self.get_all_elements(context, xpath, msg = nil)
    visible = true
    elems = context.all(xpath)
    if !elems
      visible = false
      elems = context.all(xpath, :visible => false)
    end
    @logger.debug %Q[#{msg} - visible: #{visible} -  xpath = `#{xpath}` - #{elems.inspect}]
    elems
  end
  
=begin
usage:
    series_click(@page, [
        {msg: "order online", xpath: "//a[@id='b1']"},
        {msg: "Rapid delivery", xpath: "(//div[@id='order-type-group']//order//div)[1]"},
        {msg: "guest login", xpath: "//button[@id='guestLoginDesktop']"},
        {msg: "cafe search", xpath: "//input[@id='cafeSearch']"} #note the last xpath is not clicked
      ])
=end
  
  def series_click(context, series) 
    if series.size <= 1
      @logger.debug "series_click needs series of xpath size at least 2"
      return
    end
    
    series.each_index {|index|
      #skip the last,as the last xpath is not clicked
      break if index == (series.size - 1)
      
      click_and_wait(context, series[index], series[index+1])
    }
  end
  
  def self.click_and_wait(context, click_on_obj, wait_for_obj, step_msg = "") 
    @logger.debug "clicking on #{click_on_obj.inspect}"
    @logger.debug "waiting for #{wait_for_obj.inspect}"
    
    click_on = get_first_element(context, click_on_obj[:xpath], "click_on #{click_on_obj[:msg]}")
    
    if !click_on
      @logger.error "Failed to find #{click_on_obj[:msg]} - step: #{step_msg}"
      return false
    end
    
    click_on.trigger('click')
    WaitModule::wait_for_page_resources
    
    flag = WaitModule::conditional_wait("#{wait_for_obj[:msg]} to become accessible", 30, [context, wait_for_obj[:xpath]]) {|_p, _x|
      _p.has_xpath?(_x)
    }
    
    if !flag
      @logger.error "Failed to find #{wait_for_obj[:msg]} - step: #{step_msg}"
      return false
    end
    
    true
  end
  
  def self.print_backtrace(ex)
    "Error = #{ex.inspect} - #{ex.backtrace.join("\n")}"
  end

  def self.get_default_open_close_timings
    Hash[*(
        %w[sunday monday tuesday wednesday thursday friday saturday].map{|d|
          [d, {"opens_at"=>"closed", "closes_at" => "closed"}]
        }.flatten(1)
      )]  
  end

  def self.get_price(text)
    ((text.scan(/[\$|(USD)](\d+[.,]\d+)/) + text.scan(/[\$|(USD)](\d+)/)).flatten.first.to_f * 100).round rescue 0
  end

  def self.strip_special_chars(text)
    return nil if !text
    clean_text = ""
    text.each_byte { |x|  clean_text << x unless x > 127   }
    return clean_text
  end
  
  def self.click_pics
    ENV['DEBUG'] && ENV['BROWSER']
  end
  
  def self.capture_screenshot_and_page(output_dir, context = Capybara.current_session)
    capture_screenshot(output_dir, context)
    capture_page(output_dir, context)
  end
  
  def self.capture_screenshot(output_dir, context)
    if defined?(Capybara) && Capybara.current_session
      filename = File.join(output_dir, Time.now.to_f.to_s)
      @logger.debug "save_screenshot #{filename}.png"
      context.save_screenshot("#{filename}.png", :full => true)
    else
      @logger.debug "skipping capture_screenshot as Capybara not defined"
    end
  end
  
  def self.capture_page(output_dir, context)
    if defined?(Capybara) && Capybara.current_session
      filename = File.join(output_dir, Time.now.to_f.to_s)
      @logger.debug "save_page #{filename}.html"
      context.save_page("#{filename}.html")
    else
      @logger.debug "skipping capture_page as Capybara not defined"
    end
  end 
  
  def self.cur_page
    Capybara.current_session.save_and_open_screenshot
  end
  
  def self.cur_html
    Capybara.current_session.save_and_open_page
  end
  
=begin
Usage
UtilsModule.substr_by_brackets(cdata, '{', '}', 1)
UtilsModule.substr_by_brackets(cdata, '{', '}', 0)
UtilsModule.substr_by_brackets(cdata, '(', ')', 1)
=end
  def self.substr_by_brackets(source, start_char, end_char, skip_cnt = 0)
    matched_str = ""
    match_started = false
    balance_arr = [0, 0]
	
    source.each_byte {|cur_char|
      cur_char = cur_char.chr
      if match_started == false && cur_char == start_char 
        skip_cnt -= 1
			
        if skip_cnt < 0
          match_started = true 
        end
      end
		
      next if match_started == false
		
      balance_arr[0] += 1 if cur_char == start_char 
      balance_arr[1] += 1 if cur_char == end_char
		
      matched_str << cur_char
		
      break if balance_arr[0] == balance_arr[1]
		
    }
	
    matched_str
  end
  
  def self.titlize(str)
    str.split.map(&:capitalize).join(" ")
  end
  
  def self.sort_order_items_on_category(ordered_items)
    ordered_items.sort{|a, b|
      a = a["item"]
      b = b["item"]
      
      a["category_id"] <=> b["category_id"]
    }
  end
  
  #copy it from browser (raw form)
  def self.transform_raw_header(req_headers_str)
    lines = req_headers_str.split("\n").select{|x| x.include?(": ")}
    
    lines.map!{|x| x.strip.split(": ", 2)}

    lines.map{|x| "-H '#{x[0]}: #{x[1]}'"}
  end
  
  def self.response_header_hash(resp_headers_str)
    resp_headers_str.split("\n").map(&:strip).select{|x| x.include?(": ")}.map{|x| k, v = x.split(": ", 2); [k.downcase, v]}.to_h
  end
  
  def self.get_scraper_proxy_pref(type, integration, merchant, location = nil)
    proxy_pref = UtilsModule::get_proxy_pref(type, location) if !location.nil?
    proxy_pref = UtilsModule::get_proxy_pref(type, merchant) if !merchant.nil? && proxy_pref.nil?
    proxy_pref = UtilsModule::get_proxy_pref(type, integration) if !integration.nil? && proxy_pref.nil?
   
    return proxy_pref
  end
  
  def self.get_proxy_pref(type, proxy_pref_from)
    proxy_pref = nil
    if proxy_pref_from
      if type == "location"
        proxy_pref = proxy_pref_from.loc_proxy_pref
      elsif type == "menu"
        proxy_pref = proxy_pref_from.menu_proxy_pref
      elsif type == "ovos"
        proxy_pref = proxy_pref_from.ovos_proxy_pref
      end
    end
    return proxy_pref    
  end

  def self.round_to_minutes(time, minute_offset)
    return (time + (((time.min - time.min % minute_offset + minute_offset) - time.min) * 60))
  end
  
  def self.update_refresh_request(job_type, id, req_id, status, message = nil)
    where_clause = {:request_id => req_id, :job_type => job_type}
    if job_type == "menu"
      where_clause[:location_id] = id
    elsif job_type == "location"
      where_clause[:merchant_id] = id
    elsif job_type == "merchant"
      where_clause[:integration_id] = id
    end
    update_json = {:status => status, :message => message, :start_time => Time.now}
    if status == "processing"
      instance_id = %x[curl --max-time 10 --stderr /dev/null http://169.254.169.254/latest/meta-data/instance-id]
      if !instance_id || instance_id.size < 3
        @logger.error "Failed to get instance id"
      else
        update_json[:instance_id] = instance_id
      end      
    end
    RefreshRequest.where(where_clause).update_all(update_json)            
  end
  
  def self.geokit_parse_address(address)
    Geokit::Geocoders::GoogleGeocoder.api_key = 'AIzaSyAJMk9xYfWhW84M0TSFGWBf6EVgMJjJibc'
    Geokit::Geocoders::GoogleGeocoder.geocode(address)
  end
  
  def self.geocodio_parse_address(address)
     geocodio = Geocodio::Client.new('51ac1e33051315e31433c513a3c8153ae10ec51')
     geocodio.geocode([address]).best
  end
end
