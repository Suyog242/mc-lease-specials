require 'json'
require 'ap'
require_relative "../../output_formats/base_format"

class OpFormat < BaseFormat
  attr_accessor  :disclaimer3
  def initialize
    super
    @disclaimer3 = nil
  end
end