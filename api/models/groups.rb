class Group
  include DataMapper::Resource
  property :id, Serial

  belongs_to :account

  has n, :reports

  property :token, String, :length => 128
  property :name, String, :length => 128
  property :email_recipient, String, :length => 255
  property :due_day, String, :length => 30
  property :due_time, DateTime   # Only the Time portion of this is used
  property :due_timezone, String, :length => 100
  property :send_reminder, Integer  # Number of hours before the deadline to send a reminder email

  property :created_at, DateTime
end