require_relative "../../output_formats/base_format"

class OpFormat < BaseFormat
  attr_accessor  :offer5, :offer6, :offer7, :dealer_contribution
  def initialize
    super
    @offer5 = nil
    @offer6 = nil
    @offer7 =nil
    @dealer_contribution = nil
  end
end