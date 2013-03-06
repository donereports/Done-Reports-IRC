class Repo
  include DataMapper::Resource
  property :id, Serial

  belongs_to :group

  has n, :commits
  
  property :link, String, :length => 255

  property :created_at, DateTime
  property :updated_at, DateTime

  def name
    return "" if link.nil? or link == ""
    link.match(/\/([^\/]+\/[^\/]+)$/)[1]
  end

  def message # The email template expects to be able to call "message" on objects
    name
  end
end
