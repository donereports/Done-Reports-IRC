class User
  include DataMapper::Resource
  property :id, Serial

  belongs_to :account
  has n, :commits
  has n, :groups, :through => :group_user

  property :username, String, :length => 255
  property :email, String, :length => 255
  property :github_email, String, :length => 255
  property :github_username, String, :length => 255
  property :gitlab_email, String, :length => 255
  property :gitlab_username, String, :length => 255
  property :gitlab_user_id, Integer
  property :nicks, String, :length => 512
  property :active, Boolean, :default => true

  property :created_at, DateTime
end