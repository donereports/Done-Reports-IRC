class Report
  include DataMapper::Resource
  property :id, Serial

  belongs_to :group

  property :date_started, DateTime
  property :date_completed, DateTime

  property :created_at, DateTime
end