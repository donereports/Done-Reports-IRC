class Group
  include DataMapper::Resource
  property :id, Serial

  belongs_to :account
  has n, :reports
  has n, :users, :through => Resource

  property :token, String, :length => 128
  property :github_token, String, :length => 32
  property :irc_channel, String, :length => 100
  property :name, String, :length => 128
  property :email_recipient, String, :length => 255
  property :due_day, String, :length => 30
  property :due_time, DateTime   # Only the Time portion of this is used
  property :due_timezone, String, :length => 100
  property :send_reminder, Integer  # Number of hours before the deadline to send a reminder email

  property :github_organization, String, :length => 100
  property :github_access_token, String, :length => 255

  property :gitlab_api_url, String, :length => 255
  property :gitlab_private_token, String, :length => 255

  property :created_at, DateTime
end