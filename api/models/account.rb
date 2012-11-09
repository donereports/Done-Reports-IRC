class Account
  include DataMapper::Resource
  property :id, Serial

  has n, :groups

  property :name, String, :length => 128

  property :created_at, DateTime
end