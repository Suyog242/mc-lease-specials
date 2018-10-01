require 'logger'
require 'pry'
require "./extracters/volvo/extractor"

RSpec.configure do |config|
  config.failure_color = :red
  config.success_color = :green
  config.tty = true
  config.color = true
end

describe Extractor do
  before :all do
    @logger = Logger.new(STDOUT)
    make = "volvo"
    zipcode = ["32044","90001","36003","06404","99553"].sample
    @logger.info "#{zipcode} selected for testing #{make}"
    extr = Extractor.new(make, zipcode)
    @logger.info "Loading target pages"
    extr.load_target_page()
    extr.set_zip_code()
    @response = extr.extract_data()
  end
  it "Check if record count is zero in final response" do
    response =  @response["lease_data"].size
    expect(response).not_to be 0
  end
end
