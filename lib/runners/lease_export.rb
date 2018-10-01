require 'csv'
require 'pry'
require 'ap'
require 'json'
require 'rubyXL'
require "open3"
require 'logger'

def main
  make_zipcode = []
  max_allowed = 3
  date = (Date.today).strftime('%Y-%m-%d')
  
  export_dir = "#{ENV["HOME"]}/lease_export/#{date}"
  log_dir = "#{ENV["HOME"]}/lease_export/logs/#{date}"
  system("mkdir -p #{export_dir}")
  system("mkdir -p #{log_dir}")
  
  invalid_makes = ["aston", "ferrari", "bentley", "fcs", "fcs", "lamborghini", "mercury", "rolls","maserati","porsche"]
  gm_makes = ["chevrolet", "cadillac", "gmc", "buick"]
  fca_makes = ["chrysler", "dodge", "jeep", "ram", "fiat"]
  
  logger = Logger.new(STDOUT)
  logger = Logger.new("#{log_dir}/lease_export.log", 10, 10240000)
  workbook = RubyXL::Parser.parse './lib/export/zipcode_make.xlsx'
  
  worksheets = workbook.worksheets
  logger.debug "Found #{worksheets.count} worksheets"

  worksheets.each do |worksheet|
    logger.debug "Reading: #{worksheet.sheet_name}"
    num_rows = 0
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
      
      num_rows += 1
    end
    puts "Read #{num_rows} rows"
  end
  
  temp_data = []
  make_zipcode.each{|make, zip|
    require_relative "../extracters/#{make}/op_format"
    _object =  OpFormat.new()
    _object.instance_variables.each {|_var| temp_data << "#{_var.to_s.gsub(/\@/,"")}"  }
  }
  
  headers = temp_data.uniq.map{|f| f.downcase}.sort
  CSV.open("#{export_dir}/chrome_headers.csv", "w") { |csv|  csv << headers }
  CSV.open("#{export_dir}/chrome_export.csv", "a") { |csv|  csv << headers } if !File.exist?("#{export_dir}/chrome_export.csv")
  
  process_executed = 0
  total_processed = 0
  make_zipcode = make_zipcode.uniq.shuffle
  total_zipcodes = make_zipcode.size
  logger.debug "Total no of Zipcodes = #{total_zipcodes}"
  
  while(!make_zipcode.empty?)
    stdin, stdout, stderr = Open3.popen3("ps -ef | grep ./makewise_export.rb | grep -v 'grep'| grep -v 'sh -c' | wc -l")
    
    process_in_progress = stdout.read.to_i
    process_to_start = max_allowed - process_in_progress
    logger.debug " --> Currently #{process_in_progress} Process executing and max allow processes #{max_allowed}... Forking #{process_to_start} process."
    
    if process_to_start > 0
      make_zipcode.pop(process_to_start).each do |make, zipcode|
        if make
          logger.debug "make => #{make} || zipcode => #{zipcode}"
          logger.debug "process in progress => #{process_executed}"
          cmd = "LANG=en_US.UTF-8  LC_CTYPE=en_US.UTF-8 ruby ./lib/runners/makewise_export.rb \"#{make}\" \"#{zipcode}\" \"#{export_dir}\""
          logger.debug("cmd - #{cmd}")
          job = fork do
            exec cmd
          end
          
          Process.detach(job)
          
        else
          logger.debug "Make not found for zipcode #{zipcode}"
        end
        
        process_executed += 1
        total_processed += 1
        logger.debug "Total zipcodes processed #{total_processed}/#{total_zipcodes} Pending : #{make_zipcode.size}"
      end
      if make_zipcode.size == 0
        logger.debug "DONE .......!!!!!!!"
      end
    end
    
  end
  
end

if __FILE__ == $0
  main
end
