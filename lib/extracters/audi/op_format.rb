require_relative "../../output_formats/base_format"

class OpFormat < BaseFormat
  attr_accessor :effective_zip , :dist_between_two_zip
  def initialize
    super
    @dist_between_two_zip = nil
    @effective_zip = nil
    #@msrp = nil
    #@aquisition_fee = nil
  end
end