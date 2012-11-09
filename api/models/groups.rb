class Group
  include DataMapper::Resource
  property :id, Serial

  belongs_to :account

  has n, :reports

  property :token, String, :length => 128
  property :name, String, :length => 128
  property :email_recipient, String, :length => 255
  property :due_day, String, :length => 30
  property :due_time, DateTime
  property :due_timezone, String, :length => 100

  property :created_at, DateTime
end