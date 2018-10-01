require 'json'
require 'ap'
require_relative "../../output_formats/base_format"

class OpFormat < BaseFormat
  attr_accessor :due_at_signing
  def initialize
    super
    
    @due_at_signing = nil
  end
end