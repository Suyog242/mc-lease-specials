require 'logger'
require 'pry'
require "./extracters/acura/extractor"

RSpec.configure do |config|
  config.failure_color = :red
  config.success_color = :green
  config.tty = true
  config.color = true
end

describe Extractor do
  before :all do
    @logger = Logger.new(STDOUT)
    make = "acura"
    zipcode = ["36003","10451","12007"].sample
    @logger.info "#{zipcode} select for testing #{make}"
    extr = Extractor.new(make, zipcode)
    @logger.info "Loading traget pages"
    @website_response = extr.load_target_page()
    @offers = []
    @website_response["Offers"].each {|_offer| @offers << _offer["SalesProgramType"]}
    extr.set_zip_code()
    @response = extr.extract_data()
  end
  it "Check SalesProgramType in website response" do
    response = "Lease" if @offers.uniq.include?"Lease"
    expect(response).to eql "Lease"
  end
  it "Check if record count is zero in website response " do
    response =  @website_response["Offers"].size
    expect(response).not_to be == 0
  end
  it "Check if record count is zero in final response" do
    response =  @response["lease_data"].size
    expect(response).not_to be 0
  end
end
