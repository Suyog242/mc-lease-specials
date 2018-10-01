require_relative "../../output_formats/base_format"

class OpFormat < BaseFormat
  attr_accessor :dealer_name, :dealer_url, :offer5
  def initialize
    super
    @dealer_name = nil
    @dealer_url = nil
    @offer5 = nil
  end
end