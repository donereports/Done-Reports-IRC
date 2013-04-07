class Group
  include DataMapper::Resource
  property :id, Serial

  belongs_to :org
  # belongs_to :ircserver
  has n, :reports
  has n, :users, :through => :group_user

  property :token, String, :length => 128
  property :github_token, String, :length => 32
  property :name, String, :length => 128
  property :email_recipient, String, :length => 255
  property :due_day, String, :length => 30
  property :due_time, DateTime   # Only the Time portion of this is used
  property :due_timezone, String, :length => 100
  property :send_reminder, Integer  # Number of hours before the deadline to send a reminder email

  property :irc_channel, String, :length => 100
  property :zenircbot_url, String, :length => 255 # URL of the zenircbot web-proxy service
  property :zenircbot_token, String, :length => 100 # Optional auth token for the web-proxy service

  property :github_organization, String, :length => 100
  property :github_access_token, String, :length => 255

  property :gitlab_api_url, String, :length => 255
  property :gitlab_private_token, String, :length => 255

  property :created_at, DateTime

  def slug
    irc_channel.gsub(/^#/, '').downcase
  end

  def send_irc_message(message)
    RestClient.post "#{zenircbot_url}channel/#{URI.encode_www_form_component irc_channel}", :message => message, :token => zenircbot_token
  end
end