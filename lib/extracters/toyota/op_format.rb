require 'json'
require 'ap'
require_relative "../../output_formats/base_format"

class OpFormat < BaseFormat
  attr_accessor :title5, :title6, :title7, :offer5, :offer6, :offer7, :offer8, :disclaimer3
  def initialize
    super
    @title5 = nil
    @title6 = nil
    @title7 = nil
    @offer5 = nil
    @offer6 = nil
    @offer7 = nil
    @offer8 = nil
  end
end