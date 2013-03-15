class Commit
  include DataMapper::Resource
  property :id, Serial

  belongs_to :repo
  belongs_to :user, :required => false
  
  property :user_name, String, :length => 100
  property :user_email, String, :length => 100

  property :type, String, :length => 100
  
  property :date, DateTime
  property :text, String, :length => 255
  property :link, String, :length => 255

  property :created_at, DateTime
  property :updated_at, DateTime

  # Return a string appropriate for sending to an IRC channel
  def irc_message
    if type == "commit"
      return false
    else
      prefix = repo.link.gsub(/^https?:\/\//, '')
      return "[#{prefix}] #{text} #{link}"
    end
  end

end
