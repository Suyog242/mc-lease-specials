require 'logging'
require 'yaml'
require 'date'

class BaseExtractor
  attr_accessor :make, :zipcode, :output, :config

  def initialize(make, zipcode)
    log_dir = "#{ENV["HOME"]}/projects/lease_sp_extracters/logs/#{(Date.today).strftime('%Y-%m-%d')}"
    system("mkdir -p #{log_dir}")
    @logger = Logging.logger[make]
    @logger.level = :debug
    @logger.add_appenders(
      Logging.appenders.rolling_file(
        '#{make}_logfile',
        :filename => "#{log_dir}/#{make}.log",
        :keep => 10,
        :age => 'daily',
        :roll_by => 'date',
        :truncate => false
      )
    )
    @make = make
    @zipcode = zipcode

    @config = YAML::load(File.read(File.join(File.dirname(__FILE__), "../../config/#{make}.yml")))

    #require_relative "../../../lib/extracters/#{make}/op_format"
    #@output = OpFormat.new
  end

  def load_target_page()
    @logger.error "method not implemented"
  end

  def set_zip_code()
    @logger.error "method not implemented"
  end

  def extract_lease_data()
    @logger.error "method not implemented. Supposed to return one of the output format object."
  end

  def extract_finance_data()
    @logger.error "method not implemented. Supposed to return one of the output format object."
  end
end
