require 'awesome_print'
require 'pry'
require 'net/ftp'
require 'date'

def ftp_upload(ftp_path, file)
  ftp_host ='ftp.chromedata.com' 
  ftp_user ="u309507"
  ftp_pass ="chr507"
  Net::FTP.open((ENV['FTP_HOST'] || ftp_host)) do |ftp|
    #ftp.login((ENV['FTP_USER'] || ftp_user), (ENV['FTP_PASS'] || ftp_pass))
    ftp.passive = true
    system "lftp -e \"mkdir -p #{ftp_path}; cd #{ftp_path}; put #{file}; bye\" -u #{ftp_user},#{ftp_pass} #{ftp_host}"
  end
end

def main
  date = (Date.today).strftime('%Y-%m-%d')
  export_dir = "#{ENV["HOME"]}/lease_export/#{date}"
  ftp_output_dir =  Date.today().strftime('%Y-%m-%d')
  if File.directory?(export_dir)
    ftp_upload("lease_export/#{ftp_output_dir}", "#{export_dir}/chrome_export.csv")
#    puts `wc -l "#{export_dir}/lease_export.csv"`.strip
    puts `csvfilter -f43 "#{export_dir}/chrome_export.csv" | wc -l`.strip
  end
end

if __FILE__ == $0
  usage = <<-EOU
      usage: ruby #{File.basename($0)} 
      eg: ruby #{File.basename($0)} 
  EOU
  main
end



#  system "lftp -e \"mkdir -p #{ftp_path}; cd #{ftp_path}; put #{file}; bye\" -u #{ftp_user},#{ftp_pass} #{ftp_host}"
