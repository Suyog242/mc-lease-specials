require 'json'
require 'ap'
require_relative "../../output_formats/base_format"

class OpFormat < BaseFormat
  attr_accessor :acquisition_fee, :msrp
  def initialize
    super
  end
end