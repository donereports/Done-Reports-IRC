class User
  include DataMapper::Resource
  property :id, Serial

  has n, :commits
  has n, :groups, :through => :group_user
  has n, :orgs, :through => :org_user

  property :username, String, :length => 255
  property :email, String, :length => 255
  property :github_email, String, :length => 255
  property :github_username, String, :length => 255
  property :gitlab_email, String, :length => 255
  property :gitlab_username, String, :length => 255
  property :gitlab_user_id, Integer
  property :nicks, String, :length => 512
  property :active, Boolean, :default => true
  property :is_account_admin, Boolean, :default => false

  property :created_at, DateTime

  def avatar_url
    if !github_email.nil? && github_email != ''
      "https://secure.gravatar.com/avatar/#{Digest::MD5.hexdigest(github_email)}?s=40&d=https://a248.e.akamai.net/assets.github.com%2Fimages%2Fgravatars%2Fgravatar-user-420.png"
    else
      "https://secure.gravatar.com/avatar/#{Digest::MD5.hexdigest(email)}?s=40&d=https://a248.e.akamai.net/assets.github.com%2Fimages%2Fgravatars%2Fgravatar-user-420.png"
      #"https://a248.e.akamai.net/assets.github.com/images/gravatars/gravatar-user-420.png"
    end
  end
end