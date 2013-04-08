class Ircserver
  include DataMapper::Resource
  property :id, Serial

  belongs_to :org, :required => false
  has n, :groups

  property :global, Boolean, :default => false

  property :hostname, String, :length => 255
  property :port, Integer, :default => 6667
  property :ssl, Boolean, :default => false
  property :server_password, String, :length => 255

  property :created_at, DateTime
  property :updated_at, DateTime

  def api_hash(with_password=false)
    data = {
      :hostname => hostname,
      :port => port,
      :ssl => ssl,
      :global => global
    }
    data[:password] = (server_password ? server_password : "") if with_password
    data
  end

end