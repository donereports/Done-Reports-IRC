ENV['TZ'] = 'UTC'
Encoding.default_internal = 'UTF-8'
require 'rubygems'
require 'bundler/setup'

Bundler.require
Dir.glob(['lib', 'models', 'helpers'].map! {|d| File.join File.expand_path(File.dirname(__FILE__)), d, '*.rb'}).each {|f| require f}

SiteConfig = Hashie::Mash.new YAML.load_file('config.yml')[ENV['RACK_ENV']] if File.exists?('config.yml')

class Controller < Sinatra::Base
  configure do
    set :root, File.dirname(__FILE__)

    #DataMapper::Logger.new(STDOUT, :debug)
    DataMapper.finalize
    DataMapper.setup :default, SiteConfig.database_url

    set :public_folder, File.dirname(__FILE__) + '/public'
  end
end

require_relative './controller.rb'
Dir.glob(['controllers'].map! {|d| File.join d, '*.rb'}).each do |f| 
  require_relative f
end
