require_relative "../../output_formats/base_format"

class OpFormat < BaseFormat
  attr_accessor :dealer_url, :dealer_zip, :msrp, :acquisition_fee, :due_at_signing, :dealer_contribution

  def initialize
    super
    @dealer_url = nil
    @dealer_zip = nil
    @msrp = nil
    @acquisition_fee = nil
    @due_at_signing = nil
    @dealer_contribution = nil
  end
end