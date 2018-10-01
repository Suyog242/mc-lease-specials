require 'aws-sdk'
require 'pry'
require 'net/http'
require 'uri'
require 'logging'
require 'json'

class ProxyList
  @@aws_bucket = "lu-proxy-info"
  @@aws_proxy_object = "proxy_list"
  
  @@basic_proxies = YAML.load_file(File.join(File.dirname(__FILE__), "proxies.yml"))
  
  @@static_vars = {
    pb_userpackages_api: "https://api.proxybonanza.com/v1/userpackages/<POOL_NUM>.json",
    pb_auth_key: "XrVyBMbnNljKBjePbNxEbVopWeMHaiqDJdogtUM1MTUmE5Kwim!42453",
    pb_pool_numbers: [51087, 49532, 51515, 51555]
  }
    
  def initialize
    @logger = Logging.logger[self]
    @logger.caller_tracing = true
    
    @s3_client = Aws::S3::Client.new(
#      region: 'us-east-1',   
#      access_key_id: ENV['AWS_S3_ACCESS_KEY_ID'],
#      secret_access_key: ENV['AWS_S3_SECRET_ACCESS_KEY']
    )
    @s3_resource = Aws::S3::Resource.new(
#      region: 'us-east-1',
#      access_key_id: ENV['AWS_S3_ACCESS_KEY_ID'],
#      secret_access_key: ENV['AWS_S3_SECRET_ACCESS_KEY']      
    )
    
    @current_proxies = {}
  end
  
  def get_current_proxies
    @current_proxies
  end
  
  def get_all
    resp = @s3_client.get_object(bucket: @@aws_bucket, key: @@aws_proxy_object)
    proxies = JSON.parse(resp.body.read)
    @logger.info("get_all::proxy_summary = #{proxy_summary(proxies)}")
    
    @current_proxies = proxies
    proxies
  rescue Exception => ex
    @logger.fatal ex.inspect
    @logger.fatal ex.backtrace.join("\n")
    return {}
  end
  
  def get_provider_list(provider_tag)
    all_proxies = get_all
    all_proxies[provider_tag]
  end
  
  def pb_proxy_type(pool_num)
    "pb_pool_#{pool_num}"
  end
  
  def proxy_summary(obj)
    obj = {} if obj.nil? || !obj.is_a?(Hash)
    obj.map{|ptype, list| "#{ptype} => #{list.size} proxies"}.inspect
  end
  
  def save_to_s3(proxies)
    success = false
    
    aws_obj = @s3_resource.bucket(@@aws_bucket).object(@@aws_proxy_object)
    aws_obj.put(body: JSON.pretty_generate(proxies))
    @logger.info("saved to s3 #{@@aws_bucket}/#{@@aws_proxy_object} => #{proxy_summary(proxies)}")
    
    @current_proxies = proxies
    success = true
    
    success
  rescue Exception => ex
    @logger.fatal ex.inspect
    @logger.fatal ex.backtrace.join("\n")
    return false
  end
  
  def reload
    pb_pool_numbers = @@static_vars[:pb_pool_numbers]
    
    basic_proxies_clone = JSON.parse(@@basic_proxies.to_json)
    
    pb_pool_numbers.each {|pool_num|
      basic_proxies_clone["pb_pool_#{pool_num}"] = get_pb_list(pool_num)
      @logger.info("fetched #{basic_proxies_clone["pb_pool_#{pool_num}"].size} proxies from pb pool #{pool_num}")
    }
    
    save_to_s3(basic_proxies_clone)
  end
  
  def reload_pb(pool_num)
    s3_proxies = get_all
    
    proxies = 
      if s3_proxies.keys.size == 0
        @logger.warn "S3 proxies are empty"
        @@basic_proxies
      else
        s3_proxies
      end
      
    pb_proxies = get_pb_list(pool_num)
    proxies[pb_proxy_type(pool_num)] = pb_proxies
    
    save_to_s3(proxies)
  end
  
  def get_pb_list(pool_number)
    uri = URI(@@static_vars[:pb_userpackages_api].sub(/<POOL_NUM>/, pool_number.to_s))
    req = Net::HTTP::Get.new(uri)
    req['Authorization'] = @@static_vars[:pb_auth_key]
    
    sock = Net::HTTP.new(uri.host, uri.port)
    if uri.scheme == 'https'
      sock.use_ssl = true
    end
    
    net_http_resp =sock.start {|http|
      http.request(req)
    }
    
    pb_list = []
    if net_http_resp.is_a?(Net::HTTPSuccess)
      api_resp = JSON.parse(net_http_resp.body)
      
      if !api_resp["success"]
        raise Exception.new("Failed to get pb list for pool: #{JSON.pretty_generate(api_resp)}")
      else
        pb_list = api_resp["data"]["ippacks"].map{|p| 
          "#{api_resp['data']['login']}:#{api_resp['data']['password']}@#{p['ip']}:#{p['port_http']}"
        }
      end
    else
      raise Exception.new("net/http failed: #{net_http_resp.inspect}")
    end

    pb_list
    
  rescue Exception => ex
    @logger.fatal ex.inspect
    @logger.fatal ex.backtrace.join("\n")
    return []
  end
end

=begin
Logging.logger.root.appenders = [Logging.appenders.stdout]
p = ProxyList.new()
#p.get_provider_list("onoph_static")
p.reload
#binding.pry
a = 10+1 
=end


