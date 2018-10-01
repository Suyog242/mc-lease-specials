require_relative "../../output_formats/base_format"

class OpFormat < BaseFormat
  attr_accessor :offer5
  def initialize
    super
    @offer5 = nil
  end
end