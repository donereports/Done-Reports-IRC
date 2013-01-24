class User
  include DataMapper::Resource
  property :id, Serial

  belongs_to :account

  has n, :commits

  property :username, String, :length => 255
  property :email, String, :length => 255
  property :github_email, String, :length => 255
  property :github_username, String, :length => 255

  property :created_at, DateTime
end