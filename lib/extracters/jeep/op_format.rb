require_relative "../../output_formats/base_format"

class OpFormat < BaseFormat
  attr_accessor :offer5 , :offer6
  def initialize
    super
    @offer5 = nil
    @offer6 = nil
  end
end