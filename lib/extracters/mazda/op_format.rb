require_relative "../../output_formats/base_format"

class OpFormat < BaseFormat
  attr_accessor :title5
  def initialize
    super
    @title5 = nil
  end
end