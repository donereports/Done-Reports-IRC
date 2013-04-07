class OrgUser
  include DataMapper::Resource
  belongs_to :user, :key => true
  belongs_to :org, :key => true
  property :is_admin, Boolean, :default => false
end