require_relative "../../output_formats/base_format"

class OpFormat < BaseFormat
  attr_accessor :msrp
  def initialize
    super
    @msrp = nil
  end
end