require_relative "../../output_formats/base_format"

class OpFormat < BaseFormat
  attr_accessor :dealer_url, :dealer_zip
  def initialize
    super
    @dealer_url = nil
    @dealer_zip= nil 
  end
end