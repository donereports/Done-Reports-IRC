class Account
  include DataMapper::Resource
  property :id, Serial

  has n, :groups
  has n, :users

  property :name, String, :length => 128

  property :created_at, DateTime
end