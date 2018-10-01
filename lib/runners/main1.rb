require 'getoptions'
require 'pry'

#require_relative "../output_formats/base_format"
def usage
  puts "Please provide make and zipcode"
  puts "E.g."
  puts "ruby lib/runners/main1.rb --make=abc --zipcode=123"
  exit
end

opt = GetOptions.new(%w(make=s zipcode=s))

if opt.make.nil? || opt.zipcode.nil?
  usage
end

require_relative "../../lib/extracters/#{opt.make}/extractor"
extr = Extractor.new(opt.make, opt.zipcode)

extr.load_target_page()
extr.set_zip_code()
extr.extract_lease_data()
extr.extract_finance_data()
