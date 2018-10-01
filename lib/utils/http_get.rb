require 'yaml'
require 'json'
require "uri"
require 'thread'
require 'tempfile'
require 'uri'
require "uuidtools"

=begin
this class takes care of
user-agents
proxy types
banned subnets
retry
JSON parse and retry
=end

class HttpGet
  @@user_agents = 
    File.read(File.join(File.dirname(__FILE__), "google_chrome_useragents")).split("\n")
  @@basic_proxies = YAML.load_file(File.join(File.dirname(__FILE__), "proxies.yml"))
  
  #pass proxy_list nil if not known 
  def initialize(proxy_pref, proxy_list = nil, options = {}, logger = nil)
    default_opts = {
      cache_dir: nil, 
      curl_max_time: 60, 
      fixed_ua: false,
      shuffle_prefs: false
    }
    
    options = default_opts.merge(options)
    
    cache_dir = options[:cache_dir]
    curl_max_time = options[:curl_max_time]
    fixed_ua = options[:fixed_ua]
    @shuffle_prox_prefs = options[:shuffle_prefs]
    
    @proxy_pref = proxy_pref
    

    if logger
      @logger = logger
    else
      @logger = Logging.logger[self]
      @logger.caller_tracing = true
    end
    
    @proxy_list = proxy_list || @@basic_proxies

    @cache_dir = cache_dir || "#{ENV["LU_LOG_HOME"]}/http_get_cache"
    
    
    stats_dir = "#{ENV["HOME"]}/http_get_stats"
    FileUtils.mkdir(stats_dir) rescue nil
    @stats_file = "#{stats_dir}/#{Time.now.utc.to_s.split.first}.log"
    
    @curl_max_time = curl_max_time
    @ua_string = fixed_ua ? @@user_agents.sample : nil
    
    @last_curl_status = nil
    
    @curl_stats_type = ["integer"]*4 + ["float"]*7 + ["string"]
    @curl_stats_keys = %w[http_code num_connects size_download speed_download time_appconnect time_connect 
                    time_namelookup time_pretransfer time_redirect 
                    time_starttransfer time_total url_effective]
    
    #@curl_stats_keys_short = Hash[* @curl_stats_keys.map{|x| [x, x[0] + (x[x.index('_')+1] rescue "")]}.flatten]
    @curl_stats_keys_short = Hash[* @curl_stats_keys.map{|x| [x, x]}.flatten]
    
    @writeout_str = @curl_stats_keys.map{|x| "#{x}=%{#{x}}"}.join(",")
    
    @curl_stats = []
    
    #this is for JSON parse to work
    ENV['LANG'] = 'en_US.UTF-8'
    ENV['LANGUAGE'] = 'en_US.UTF-8'
    ENV['LC_ALL'] = 'en_US.UTF-8'
  end
  
  def validate_proxy_prefs
    proxy_types_not_defined = (@proxy_pref - @proxy_list.keys) - ['none']
    if proxy_types_not_defined.size > 0
      @logger.fatal "proxy_types_not_defined = #{proxy_types_not_defined.inspect}"
      false
    else
      true
    end
  end
  
  def last_curl_status
    @last_curl_status
  end
  
  def curl_stats
    @curl_stats
  end
  
  def process_batch(batch, pool_size = 3)
    pool_size = 1 if !pool_size.is_a?(Fixnum) || pool_size < 1
    work_q = Queue.new
    batch.each_with_index{|work_item, index| work_q.push work_item.update({index: index}) }
    workers = (0..(pool_size - 1)).map do
      Thread.new do
        begin
          while work_item = work_q.pop(true)
            options = {
              json_res: work_item[:json_res], 
              curl_opts: work_item[:curl_opts], 
              tag: work_item[:tag], 
              use_ua: work_item[:use_ua], 
              cache: work_item[:cache], 
              log_response: work_item[:log_response]
            }
            work_item[:inout_hash] = {} unless work_item.has_key?(:inout_hash)
            
            resp = get(work_item[:url], options, work_item[:inout_hash])
            
            cur_batch_item = batch.select{|b| b[:index] == work_item[:index]}.first
            cur_batch_item[:response] = resp
            
            if block_given?
              yield work_item[:url], resp, work_item[:inout_hash]
            end
            @logger.debug "Response - #{work_item[:tag]} - #{resp}" if ENV["DEBUG_HTTP_GET"]
          end
        rescue ThreadError
        end
      end
    end
    workers.map(&:join)
  end
  
  def get_subnet(proxy)
    match = proxy.match(/^(\d{1,3})\.(\d{1,3})\.\d{1,3}\.\d{1,3}:/)
    match ? "#{match[1]}.#{match[2]}" : nil
  end
  
  def next_proxy(proxy_type, used_subnets)
    proxy = nil
    
    30.times {
      proxy = @proxy_list[proxy_type].sample
      subnet = get_subnet(proxy)
      
      #puts "try #{proxy}"
      
      if subnet
        if used_subnets.include?(subnet)
          #puts "used subnet"
          @logger.debug "cur subnet = #{subnet.inspect} rejected as its in used_subnets = #{used_subnets.inspect}"
          next
        else
          used_subnets << subnet
          #puts "found new subnet = #{used_subnets.inspect}"
          break
        end
      else
        break
      end
    }
    
    proxy
  end

  #---- CACHE ----
  #If you want to store response in cache then set cache=true
  #If you want to utilize cache then set ENV['USE_HTTP_CACHE'] and options[:cache]=true
  #make sure that the tag is unique
  #---- CACHE INFO END ----
  def get(url, options = {}, inout_hash = {}) 
    default_options = {
      json_res: false, 
      curl_opts: "", 
      tag: "default_tag", 
      use_ua: true, 
      cache: false, 
      log_response: false, 
    }
    
    used_subnets = []    
    options = default_options.merge(options)
    
    json_res = options[:json_res]
    curl_opts = options[:curl_opts]
    tag = options[:tag]
    use_ua = options[:use_ua]
    cache = options[:cache]
    log_response = options[:log_response]
    
    inout_hash[:tag] = options[:tag]
    
    tag_log_str = "tag=#{tag}"
    curl_opts = curl_opts.join(" ") if curl_opts.is_a? Array
    
    #tag should be unique to use cache
    if ENV['USE_HTTP_CACHE'] && cache
      cache_file_name = cached_file_name(url, tag)
      if File.exist?(cache_file_name)
        cookie_copied = false
        if curl_opts.include?(" -b ") && curl_opts.include?(" -c ")
          cookie_req_file = curl_opts.scan(/\s+\-b\s+([^\s]+)/).flatten.first
          cookie_resp_file = curl_opts.scan(/\s+\-c\s+([^\s]+)/).flatten.first
          if File.exists?(cookie_req_file)
            FileUtils.copy(cookie_req_file, cookie_resp_file)
            cookie_copied = true
          end
        end
        @logger.info "#{tag_log_str} cookie_copied = #{cookie_copied} cache HIT"
        
        if inout_hash[:required_resp_headers] == true
          resp_headers_cache_file = cached_file_name(url, tag + "resp_headers")
          if File.exists?(resp_headers_cache_file)
            @logger.info "#{tag_log_str} response headers cache HIT"
            inout_hash[:resp_headers] = File.read(resp_headers_cache_file)
          end
        end
        
        if json_res == true
          return JSON.parse(File.read(cache_file_name))
        else
          return File.read(cache_file_name)
        end
      end
    end
    
    tmpfile = Tempfile.new('http_get')
    resp_headers_tmpfile = Tempfile.new('http_get_resp_headers')
    
    response = nil
    
    invalid_request = false
    
    prefs = 
      if @shuffle_prox_prefs
        
         @proxy_pref.sort.group_by{|x| x}.values.shuffle.flatten
      else
         @proxy_pref
      end
    
    prefs.each do |proxy_type|
      proxy = (proxy_type == 'none') ? 
        'none' : (next_proxy(proxy_type, used_subnets) rescue nil)
      
      if proxy.nil?
        @logger.fatal "Failed to get sample proxy from type = #{proxy_type}"
        next
      end
      
      proxy_user, proxy_pass, proxy_host, proxy_port = proxy_parts(proxy)

      begin
        final_log_msg = "#{tag_log_str} proxy_type=#{proxy_type} proxy=#{proxy_host}"
        if use_ua == true
          curl_opts = "" if curl_opts.nil?
          if !curl_opts.include?("User-Agent: ")
            if @ua_string
              curl_opts += " -H 'User-Agent: #{@ua_string}'"
            else
              curl_opts += " -H 'User-Agent: #{@@user_agents.sample}'"
            end
          end
        end
          
        proxy_string = proxy_type == "none" ? "" : "--proxy #{proxy}"
        dump_headers =  "--dump-header #{resp_headers_tmpfile.path}"
          
        curl_cmd = %Q[curl "#{url}" #{proxy_string} -L --silent --stderr /dev/null --max-redirs 10 --max-time #{@curl_max_time} -v -o #{tmpfile.path} #{dump_headers} -w '#{@writeout_str}' #{curl_opts}]

        curl_writeout = %x[#{curl_cmd}]
        cur_stat = populate_curl_stats(curl_writeout)
        status = cur_stat['http_code'].to_i.to_s
        
        if status == "301" || status == "302" || status == "0"
          curl_cmd = %Q[curl -k "#{url}" #{proxy_string} -L --silent --stderr /dev/null --max-redirs 10 --max-time #{@curl_max_time} -v -o #{tmpfile.path} #{dump_headers} -w '#{@writeout_str}' #{curl_opts}]
          curl_writeout = %x[#{curl_cmd}]
          cur_stat = populate_curl_stats(curl_writeout)
          status = cur_stat['http_code'].to_i.to_s
        end
        
        url_effective = curl_writeout.match(/url_effective=(.+)/)[1] rescue nil
        inout_hash[:url_effective] = url_effective
        
        exit_node_ip = case proxy_type
          when "none"
            `hostname -i`.strip
          when "squid"
            proxy.split(":").first rescue begin "ERROR" end
          when "shader"
            File.read(resp_headers_tmpfile.path).
              split(/\r?\n/).
              find{|x| x.match(/X-Server-IP/i)}.
              split(": ").last rescue begin "ERROR" end
          else
            "unknown"
          end
        
        inout_hash[:status] = status
          
        #curl_stats_for_log_short = "#{Time.now.utc} #{get_stats_log_str_short(cur_stat)} #{proxy_type} #{URI.parse(url).host rescue nil}"
        curl_stats_for_log_long = "#{Time.now.utc} #{get_stats_log_str_long(cur_stat)} proxy #{proxy_type} ip #{exit_node_ip} url_host #{URI.parse(url).host rescue nil}"
        File.open(@stats_file, "a") {|file|
          file.flock(File::LOCK_EX)
          file.write(curl_stats_for_log_long + "\n")
        }
        
        out_file_contents = File.read(tmpfile.path)
        @last_curl_status = status
        final_log_msg += " status= #{status} stats = #{curl_stats_for_log_long} Curl command = #{curl_cmd}" #if ENV['DEBUG'] && attempt == 0
          
        json_test_result = nil
        resp_logged = false
        block_test = false
        
        if status.match(/2../) || status.match(/3../)
          response, json_test_result, resp_logged = process_response(json_res, out_file_contents)
        else            
          if block_given?
            got_expected_resp = yield(status, out_file_contents)
              
            if got_expected_resp
              response, json_test_result, resp_logged = process_response(json_res, out_file_contents) 
              block_test = true #only for logging
            end
              
            #400 Bad Request, 422 Unprocessable Entity, 405 Method Not Allowed
          elsif status == "400" || status == "405" || status == "422" || status == ''
            resp_logged = true
            @logger.debug("invalid request due to status = `#{status}`. Response = >>>>>#{out_file_contents}<<<<<")
            invalid_request = true
            response, json_test_result, resp_logged = process_response(json_res, out_file_contents) 
          end
            
          if status == '000'
            resp_logged = true
            @logger.debug "status 000: response = >>>>>#{out_file_contents}<<<<<"
          end
        end

        final_log_msg += " #{json_test_result} block_test=#{block_test} url=#{url}"

        if resp_logged == false && (ENV['DEBUG_HTTP_GET'] || log_response == true)
          @logger.debug final_log_msg + " response = #{response.to_s || "<NO_RESPONSE>" }"
        else
          @logger.info final_log_msg
        end
      rescue Exception => ex #ECONNREFUSED: Connection refused by proxy
        @logger.error("#{final_log_msg} error=#{ex.class} #{ex.message} #{json_test_result} url=#{url} - response #{response}")
        response = nil
      end
      
      if invalid_request
        @logger.info "tag=#{tag} no further attempts as the request is invalid"
        break
      end
      
      break if response
    end
    
    if cache
      if response
        if !File.exists?(@cache_dir)
          FileUtils.mkdir @cache_dir 
        end

        require 'digest'
        
        #response body
        cache_file_name = cached_file_name(url, tag)
        create_cached_dir(cache_file_name)
        FileUtils.copy(tmpfile, cache_file_name)
        
        #response headers
        if inout_hash[:required_resp_headers] == true && resp_headers_tmpfile
          cache_file_name = cached_file_name(url, tag + "resp_headers")
          create_cached_dir(cache_file_name)
          FileUtils.copy(resp_headers_tmpfile, cache_file_name)
        end
        
        @logger.info "tag=#{tag} cached #{url} into #{cache_file_name}"
      else
        @logger.info "tag=#{tag} skipping cache dump as response was nil"
      end
    end

    if inout_hash[:required_resp_headers] == true && resp_headers_tmpfile
      inout_hash[:resp_headers] = File.read(resp_headers_tmpfile.path)
    end
    
    if resp_headers_tmpfile
      resp_headers_tmpfile.close
      resp_headers_tmpfile.unlink
    end
    
    if tmpfile
      tmpfile.close
      tmpfile.unlink
    end
    
    return response

  rescue Exception => ex
    @logger.fatal curl_cmd rescue nil 
    @logger.fatal final_log_msg rescue nil 
    @logger.error response rescue nil
    @logger.fatal ex.inspect
    @logger.error ex.backtrace.join("\n")

    return nil
  ensure
    if tmpfile
      tmpfile.close
      tmpfile.unlink
    end
    
    if resp_headers_tmpfile
      resp_headers_tmpfile.close
      resp_headers_tmpfile.unlink
    end
  end
  
  def cached_file_name(url, tag)
    fname = Digest::SHA256.hexdigest("#{url}#{tag}")
    File.join(@cache_dir, fname[0], fname[1], fname)
  end
  
  def stats_for_refresh
    size_download = @curl_stats.reduce(0){|s,x| s + x['size_download'].to_f.round(3)}
    num_connects = @curl_stats.reduce(0){|s,x| s + x['num_connects'].to_f.round(3)}
    return [size_download, num_connects]
  rescue Exception => ex
    @logger.fatal "Failed to get stats_for_refresh"
    @logger.fatal ex.inspect
    return [0,0]
  end
  private
  
  def process_response(json_res, out_file_contents)
    response = nil
    resp_logged = false
    ascii_out_file_contents = remove_non_ascii(out_file_contents)
    
    if json_res == true
      begin
        response = JSON.parse(ascii_out_file_contents)
        json_test_result = "json_test_result=passed"
      rescue Exception => ex
        json_test_result = "json_test_result=failed"
        @logger.error "json_test_result=failed #{ex.inspect}"
        resp_logged = true
        @logger.error "ascii_out_file_contents = #{ascii_out_file_contents}"
      end
    else
      response = ascii_out_file_contents
      json_test_result = "json_test_result=na"
    end
    
    [response, json_test_result, resp_logged]
  end
  
  def remove_non_ascii(text)
    ascii_out_file_contents = ""
    text.each_byte { |x|  ascii_out_file_contents << x unless x > 127 }
    ascii_out_file_contents
  end
  
  def proxy_parts(proxy)
    userpass, proxy_user, proxy_pass = [nil]*3
    if proxy.include?("@")
      userpass, proxy = proxy.split("@")
      proxy_user, proxy_pass = userpass.split(":")
    end
    
    proxy_host, proxy_port = proxy.split(":")
    [proxy_user, proxy_pass, proxy_host, proxy_port]
  end
  
  def subnet(ip)
    class_a, class_b, _, _ = ip.split('.')
    "#{class_a}.#{class_b}"
  end
  
  def create_cached_dir(fname)
    fname = File.basename(fname)
    FileUtils.mkdir_p(File.join(@cache_dir, fname[0], fname[1])) rescue nil
  end
  
  def get_stats_log_str_long(single_stat)
    log_str_arr = []
    single_stat.each_pair{|k, v|
      log_str_arr << [@curl_stats_keys_short[k], v]
    }
    
    log_str_arr.map{|x| "#{x[0]} #{x[1]}"}.join(" ")
  end
  
  def get_stats_log_str_short(single_stat)
    single_stat.values.join(" ")
  end
  
  def populate_curl_stats(curl_output)
    opt_part = curl_output.split(",")
    
    single_stat = {}
    index = 0
    opt_part.each {|opt|
      key_name, value = opt.split('=').map(&:strip)
      single_stat[key_name] = 
        case @curl_stats_type[index]
        when "integer"
          value.to_i
        when "float"
          value.to_f.round(3)
        when "string"
          value.to_s
        end
      
      index += 1
    }
    
    single_stat['effective_host'] = URI.parse(single_stat['url_effective']).host rescue nil   
    @curl_stats << single_stat
    single_stat
  end
  
  def avg_curl_stats_str
    sample_size = @curl_stats.size
    sample_size = 1 if sample_size == 0
    
    avg_stats = []
    
    @curl_stats_keys.size.times {|index|
      sum = @curl_stats.reduce(0){|s,x| s + x[@curl_stats_keys[index]].to_f.round(3)}
      avg_stats << [@curl_stats_keys[index], (sum/sample_size).round(3)].join("= ")
    }
    
    avg_stats.join(" , ")
  end
end
