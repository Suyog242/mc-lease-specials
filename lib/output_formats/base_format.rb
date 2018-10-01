require 'awesome_print'
require 'htmlentities'

class BaseFormat
  attr_accessor :offer_type, :zip, :brand, :model_details, :apr_rate, :cashback_amount, :emi, :emi_months, :down_payment, :due_at_signing, :offer_start_date, :offer_end_date, :security_deposit, 
    :msrp, :mileage_charge, :acquisition_fee, :disposition_fee, :tax_registration_exclusion, :title1, :title2, :title3, :title4, :offer1, 
    :offer2, :offer3, :offer4, :disclaimer1, :disclaimer2, :other_disclaimer

  def initialize()
    @offer_type = nil
    @zip = nil
    @brand = nil
    @model_details = nil
    @apr_rate = nil
    @cashback_amount = nil
    @emi = nil
    @emi_months = nil
    @down_payment = nil
    @due_at_signing = nil
    @offer_start_date = nil
    @offer_end_date = nil
    @security_deposit = nil
    @msrp = nil
    @mileage_charge = nil
    @acquisition_fee = nil
    @disposition_fee = nil
    @tax_registration_exclusion = nil
    @title1 = nil
    @title2 = nil
    @title3 = nil
    @title4 = nil
    @offer1 = nil
    @offer2 = nil
    @offer3 = nil
    @offer4 = nil
    @disclaimer1 = nil
    @disclaimer2 = nil
    @other_disclaimer = nil
  end
  def self.convert_to_json(arr_objects , data_type)
    final_output = {}
    final_output["#{data_type}"] = []
    arr_objects.each do |_object|
      temp_data = {}
      _object.instance_variables.each {|_var| temp_data["#{_var.to_s.gsub(/\@/,"")}"] = nil }
      temp_data.each { |index, value| temp_data[index]=_object.send(index) }
      final_output["#{data_type}"] << temp_data
    end
    ap final_output
    return final_output
  end
  def self.parse_text(string)
    return nil if string.nil?
    clean_text = ""
    string.to_s.each_byte { |x|  clean_text << x unless x > 127 }
    clean_text = HTMLEntities.new.decode(clean_text.strip.gsub(/\n+|\s+/, " ").gsub(/[\u0080-\u00ff]/, " "))
    clean_text.force_encoding("UTF-8")
    return clean_text
  end
end 