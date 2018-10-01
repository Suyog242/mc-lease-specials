require_relative "../../output_formats/base_format"

class OpFormat < BaseFormat

  def initialize
    super
  end
  attr_accessor :due_at_signing, :msrp
  def initialize
    super
    @due_at_signing = nil
    @msrp = nil
    

  end
end