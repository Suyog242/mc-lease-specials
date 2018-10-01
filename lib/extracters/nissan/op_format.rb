require 'json'
require 'ap'
require_relative "../../output_formats/base_format"

class OpFormat < BaseFormat
  attr_accessor  :offer5, :disclaimer3, :disclaimer4, :disclaimer5, :offer6
  def initialize
    super
    @offer5 = nil
    @offer6 = nil
    @disclaimer3 = nil
    @disclaimer4 = nil
    @disclaimer5 = nil
  end
end