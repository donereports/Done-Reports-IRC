class Ircserver
  include DataMapper::Resource
  property :id, Serial

  property :hostname, String, :length => 255
  property :port, Integer, :default => 6667
  property :ssl, Boolean, :default => false
  property :server_password, String, :length => 255

  property :created_at, DateTime
  property :updated_at, DateTime
end