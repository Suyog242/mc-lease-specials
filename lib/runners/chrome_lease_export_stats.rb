require "rubygems"
require "logger"
require "ap"
require 'csv'
require 'net/http'
require "uri"
require 'open3'
require 'fileutils'
require "json"
require 'net/ftp'
require 'net/smtp'
require 'pry'
require 'mail'
require 'rubyXL'
require 'base64'

def send_mail_notification(out_dir)
  hostname = `hostname`.strip.upcase
  Mail.defaults do
    delivery_method :smtp, :address     => ENV["SMTP_HOST"],
      :port       => ENV["SMTP_PORT"],
      :user_name  => ENV["SMTP_USER"],
      :password   => ENV["SMTP_PASSWORD"],
      :domain     => ENV["SMTP_DOMAIN"],
      :from       => ENV["SMTP_EMAIL"],
      :enable_ssl => true
  end
  mail = Mail.new do
    from     ENV["SMTP_EMAIL"]
    to       'developers@zerebral.co.in'
    subject  "Chrome lease specials export file stats #{(Date.today).strftime('%Y-%m-%d')} - #{hostname} "
  end
  mail.attachments["chrome_export_stats.csv"] = {content: Base64.encode64(File.read("#{out_dir}/chrome_export_stats.csv")), transfer_encoding: :base64}
  mail.deliver!
end

begin
  make_zipcode , @diff_count = [] , []
  output_dir = "#{ENV["HOME"]}/lease_export"
  date = (Date.today).strftime('%Y-%m-%d')
  stats_dir = "#{output_dir}/#{date}"
  last_lease_file = "#{output_dir}/#{(Date.today-1).strftime('%Y-%m-%d')}/chrome_export.csv"
  recent_lease_file = "#{output_dir}/#{(Date.today).strftime('%Y-%m-%d')}/chrome_export.csv"
  
  invalid_makes = ["aston", "ferrari", "bentley", "fcs", "fcs", "lamborghini", "mercury", "rolls","maserati","porsche"]
  gm_makes = ["chevrolet", "cadillac", "gmc", "buick"]
  fca_makes = ["chrysler", "dodge", "jeep", "ram", "fiat"]
  
  workbook = RubyXL::Parser.parse './lib/export/zipcode_make.xlsx'
  worksheets = workbook.worksheets
  worksheets.each do |worksheet|
    worksheet.each_with_index do |row, idx|
      next if idx == 0
      row_cells = row.cells.map{ |cell| cell.value }
      make, zipcode = row_cells[0].split(" ",2)[0].split(/-|\//, 2)[0].downcase,  row_cells[1]
      next if invalid_makes.include?(make)
      make = "#{make}_rover" if make == "land"
      if(make == "gm")
        gm_makes.each {|_make| make_zipcode << [_make,zipcode]} 
      elsif (make == "fca")
        fca_makes.each {|_make| make_zipcode << [_make,zipcode]} 
      else    
        make_zipcode << [make, zipcode]
      end
    end
  end
 temp_data = []
 make_zipcode.each{|make, zip|
    require_relative "../extracters/#{make}/op_format"
    _object =  OpFormat.new()
    _object.instance_variables.each {|_var| temp_data << "#{_var.to_s.gsub(/\@/,"")}"  }
  }
  
  headers = temp_data.uniq.map{|f| f.downcase}.sort
  
  
  CSV.open("#{stats_dir}/chrome_export_stats.csv", "w", :col_sep => ",") do |csv|
    csv << ["ZIPCODE", "BRAND","PREVIOUS_COUNT","CURRENT_COUNT","COUNT_DIFF"]
  end
  
   CSV.open("#{stats_dir}/zero_records.csv", "w", :col_sep => ",") do |csv|
    csv << ["ZIPCODE", "BRAND","PREVIOUS_COUNT","CURRENT_COUNT","COUNT_DIFF"]
   end
  
  scraped_makes = `csvfilter -f#{headers.find_index("brand")} #{recent_lease_file} | sort -u`.split("\r\n")
  
  work_q = Queue.new
  scraped_makes.each do |_make|
    next if _make == "brand"
    work_q.push _make
  end
  
  @final_makes_diff = []
  @zero_record = []
  parallel = work_q.size > 16 ? 16 : work_q.size-1 #max 10 threads
  parallel = 1 if parallel < 1
  workers = (0...parallel).map do |thread_id|
    Thread.new do
      begin
        while _make = work_q.pop(true)
          make_zipcode.each do |_input_make, _zip|
            next if _input_make.downcase != _make.downcase
            prev_zipwise_count = `csvfilter -f#{headers.find_index("brand")},#{headers.find_index("zip")} #{last_lease_file} | grep #{_make} | grep #{_zip} | wc -l`.gsub("\n","").to_i
            curr_zipwise_count = `csvfilter -f#{headers.find_index("brand")},#{headers.find_index("zip")} #{recent_lease_file} | grep #{_make} | grep #{_zip} | wc -l`.gsub("\n","").to_i
            count_diff = curr_zipwise_count - prev_zipwise_count
	    puts "Zipwise comparision #{_make} #{_zip} #{prev_zipwise_count} #{curr_zipwise_count} #{count_diff}"
            @final_makes_diff << [_zip, _make, prev_zipwise_count, curr_zipwise_count, count_diff] if count_diff != 0
            @zero_record << [_zip, _make, prev_zipwise_count, curr_zipwise_count, count_diff] if curr_zipwise_count == 0
	 end
        end
      rescue ThreadError
        puts "DThread #{thread_id} - No jobs in queue to process"
      end
    end
  end
  workers.map(&:join);
  
  @final_makes_diff.each do |_out|
    CSV.open("#{stats_dir}/chrome_export_stats.csv", "a") { |csv| csv << _out }
  end
	  
@zero_record.each do |_out|
    CSV.open("#{stats_dir}/zero_records.csv", "a") { |csv| csv << _out }
  end
  send_mail_notification(stats_dir)
end
