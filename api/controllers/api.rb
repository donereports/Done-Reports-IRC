class Controller < Sinatra::Base

  def validate_access_token(token)
    if token == "" or token == nil
      halt json_error(200, {
        :error => 'access_token_required', 
        :error_description => 'Must provide a token'
      })
    end

    begin
      tokenInfo = JWT.decode(token, SiteConfig.token_secret)
    rescue
      halt json_error(200, {
        :error => 'invalid_token', 
        :error_description => 'The token provided could not be validated'
      })
    end

    user = User.first :id => tokenInfo['user_id']

    if user.nil?
      halt json_error(200, {
        :error => 'user_not_found', 
        :error_description => "The user account was not found (#{tokenInfo['user_id']})"
      })
    end

    if user.active == false
      halt json_error(200, {
        :error => 'user_inactive', 
        :error_description => "The user account is not active (#{user.username})"
      })
    end

    user
  end

  def user_can_admin_group?(user, group)
    return true if user_can_admin_org?(user, group.org)
    link = user.group_user.first(:group => group)
    return false if link.nil?
    return link.is_admin == true
  end

  # TODO: New method user_can_admin_org?(user, org)
  def user_can_admin_org?(user, org)
    link = user.org_user.first(:org => org)
    return false if link.nil?
    return link.is_admin == true
  end

  def generate_access_token(user)
    JWT.encode({:user_id => user.id}, SiteConfig.token_secret)
  end

  get '/auth/github' do
    if params[:code]
      result = RestClient.post "https://github.com/login/oauth/access_token", {
        :client_id => SiteConfig.github_id,
        :client_secret => SiteConfig.github_secret,
        :code => params[:code]
      }, {
        :accept => :json
      }

      accessToken = JSON.parse(result)["access_token"]
      userInfo = JSON.parse(RestClient.get "https://api.github.com/user", {:params => {:access_token => accessToken}})

      # Find the user by their Github login (Github accounts can only belong to a single user across all Done accounts)
      puts userInfo['login'].inspect
      user = User.first :github_username => userInfo['login']

      if user.nil?
        halt json_error(200, {
          :error => 'user_not_found'
        })
      end

      token = generate_access_token user

      if session[:state] != params[:state]
        json_error(200, {
          :error => 'invalid_state'
        })
      end

      if session[:redirect]
        uri = URI.parse session[:redirect]
        uri.fragment = "username=#{user.username}&access_token=#{token}"
        redirect uri.to_s
      else
        json_response(200, {
          :username => user.username,
          :access_token => token
        })
      end
    else
      # Start the Github login flow now
      session[:redirect] = params[:redirect] if params[:redirect]
      session[:state] = SecureRandom.urlsafe_base64(20)
      redirect "https://github.com/login/oauth/authorize?client_id=#{SiteConfig.github_id}&state=#{session[:state]}"
    end
  end

  get '/api/self' do
    auth_user = validate_access_token params[:access_token]

    json_response(200, {
      :username => auth_user.username,
      :email => auth_user.email
    })
  end

  # Retrieve all users for all orgs, including the list of channels each user is in
  # Does not include deactivated users
  get '/api/users' do
    auth_user = validate_access_token params[:access_token]

    users = []
    auth_user.orgs.all.each do |org|
      org.users.all(:active => true).each do |user|
        users << {
          :username => user.username,
          :email => user.email,
          :nicks => user.nicks,
          :active => user.active,
          :groups => user.groups.all(:org => org).collect {|group|
            {
              :slug => group.slug,
              :name => group.name,
              :channel => group.irc_channel,
            }
          }
        }
      end
    end

    json_response(200, {
      :users => users
    })
  end

  # Get a list of all groups the authenticated user has access to across all orgs
  get '/api/groups' do
    auth_user = validate_access_token params[:access_token]

    orgs = []
    auth_user.orgs.each do |org|
      orgInfo = {
        :name => org.name,
        :groups => []
      }

      orgInfo[:groups] = (user_can_admin_org?(auth_user, org) ? org.groups : auth_user.groups).collect { |group|
        zone = Timezone::Zone.new :zone => group.due_timezone
        time = group.due_time.to_time.strftime("%l:%M%P").strip

        {
          :slug => group.slug,
          :name => group.name,
          :channel => group.irc_channel,
          :timezone => group.due_timezone,
          :time => time,
          :members => group.users.length,
          :is_admin => user_can_admin_group?(auth_user, group)
        }
      }

      orgs << orgInfo
    end

    json_response(200, {
      :orgs => orgs
    })
  end

  get '/api/orgs/:org/groups/:group' do
    auth_user = validate_access_token params[:access_token]

    org = Org.first(:name => params[:org])
    if org.nil?
      halt json_error(200, {
        :error => 'not_found',
        :error_description => 'The organization was not found'
      })
    end

    org_user = auth_user.org_user.first(:org => org)
    if org_user.nil?
      halt json_error(200, {
        :error => 'forbidden',
        :error_description => 'The user does not have access to this organization'
      })
    end

    group = Group.first :irc_channel => "##{params[:group]}", :org => org
    if group.nil?
      halt json_error(200, {
        :error => 'group_not_found', 
        :error_description => 'The specified group was not found'
      })
    end

    zone = Timezone::Zone.new :zone => group.due_timezone
    time = group.due_time.to_time.strftime("%l:%M%P").strip

    json_response(200, {
      :slug => group.slug,
      :name => group.name,
      :channel => group.irc_channel,
      :timezone => group.due_timezone,
      :time => time,
      :members => group.users.length,
      :is_admin => user_can_admin_group?(auth_user, group)
    })
  end

  post '/api/orgs/:org/groups' do
    auth_user = validate_access_token params[:access_token]

    org = Org.first(:name => params[:org])
    if org.nil?
      halt json_error(200, {
        :error => 'not_found',
        :error_description => 'The organization was not found'
      })
    end

    if !user_can_admin_org?(auth_user, org)
      halt json_error(200, {
        :error => 'forbidden',
        :error_description => 'Only organization admins can add groups'
      })
    end

    if params[:channel].nil? || params[:channel] == ''
      halt json_error(200, {
        :error => 'missing_input',
        :error_description => 'Channel is required'
      })
    end

    group = Group.first :irc_channel => "#{params[:channel]}", :org => org

    if !group.nil?
      halt json_error(200, {
        :error => 'already_exists',
        :error_description => 'A group already exists for the specified channel'
      })
    end

    group = Group.create({
      org: org,
      irc_channel: "#{params[:channel]}",
      token: SecureRandom.urlsafe_base64(32),
      name: params[:name],
      due_day: 'every',
      due_time: DateTime.parse('2000-01-01 21:00:00'),
      due_timezone: 'America/Los_Angeles',
      send_reminder: 2,
      github_token: SecureRandom.urlsafe_base64(12),
      zenircbot_url: SiteConfig.zenircbot_url,
      zenircbot_token: SiteConfig.zenircbot_token
    })

    zone = Timezone::Zone.new :zone => group.due_timezone
    time = group.due_time.to_time.strftime("%l:%M%P").strip

    json_response(200, {
      :slug => group.slug,
      :name => group.name,
      :channel => group.irc_channel,
      :timezone => group.due_timezone,
      :time => time,
      :is_admin => user_can_admin_group?(auth_user, group)
    })
  end

  get '/api/orgs/:org/groups/:group/users' do
    auth_user = validate_access_token params[:access_token]

    org = Org.first(:name => params[:org])
    if org.nil?
      halt json_error(200, {
        :error => 'not_found',
        :error_description => 'The organization was not found'
      })
    end

    org_user = auth_user.org_user.first(:org => org)
    if org_user.nil?
      halt json_error(200, {
        :error => 'forbidden',
        :error_description => 'The user does not have access to this organization'
      })
    end

    group = Group.first :irc_channel => "##{params[:group]}", :org => org
    if group.nil?
      halt json_error(200, {
        :error => 'group_not_found', 
        :error_description => 'The specified group was not found'
      })
    end

    users = []
    group.users.all(:active => true).each do |user|
      users << {
        :username => user.username,
        :email => user.email,
        :nicks => user.nicks
      }
    end

    json_response(200, {
      :users => users
    })
  end

  # Get user account info
  get '/api/users/:username' do
    auth_user = validate_access_token params[:access_token]

    user = User.first({
      :account_id => auth_user.account_id,
      :username => params[:username]
    })

    if user.nil?
      halt json_error(200, {
        :error => 'user_not_found', 
        :error_description => 'The specified user was not found'
      })
    end

    # TODO: wrap in user.orgs list
    groups = user.groups.collect {|group|
      {
        :slug => group.slug,
        :name => group.name,
        :channel => group.irc_channel,
        :timezone => group.due_timezone,
      }
    }

    json_response(200, {
      :username => user.username,
      :email => user.email,
      :github_username => user.github_username,
      :github_email => user.github_email,
      :gitlab_username => user.gitlab_username,
      :gitlab_user_id => user.gitlab_user_id,
      :gitlab_email => user.gitlab_email,
      :nicks => user.nicks,
      :groups => groups
    })
  end

  # Update user profile info
  post '/api/users/:username' do
    auth_user = validate_access_token params[:access_token]

    user = User.first({
      :account_id => auth_user.account_id, 
      :username => params[:username]
    })

    if user.nil?
      halt json_error(200, {
        :error => 'user_not_found',
        :error_description => 'No user was found with the specified username'
      })
    end

    # Find out if the authenticated user is an admin for any groups this user belongs to
    can_edit = false
    user.groups.each do |group|
      can_edit = true if user_can_admin_group? auth_user, group
    end

    if !can_edit
      halt json_error(200, {
        :error => 'forbidden',
        :error_description => 'You can only edit a user if you administer at least one of the groups the user belongs to'
      })
    end

    fields_updated = []
    [:email, :github_username, :github_email, :gitlab_username, :gitlab_email, :nicks].each do |field|
      if !params[field].nil?
        user[field] = params[field]
        fields_updated << field
      end
    end

    if params[:gitlab_user_id] === ''
      user.gitlab_user_id = nil
      fields_updated << :gitlab_user_id
    end

    if fields_updated.count > 0
      user.save
    end

    json_response(200, {
      :result => 'updated',
      :updated => fields_updated,
      :username => user.username,
    })    
  end

  # Add an existing user to a group
  post '/api/users/:username/groups' do
    auth_user = validate_access_token params[:access_token]

    if params[:org].nil?
      halt json_error(200, {
        :error => 'missing_input',
        :error_description => 'Parameter \'org\' is required'
      })
    end

    org = Org.first(:name => params[:org])
    if org.nil?
      halt json_error(200, {
        :error => 'not_found',
        :error_description => 'The organization was not found'
      })
    end

    group = Group.first :irc_channel => "##{params[:group]}", :org => org
    if group.nil?
      halt json_error(200, {
        :error => 'group_not_found', 
        :error_description => 'The specified group was not found'
      })
    end

    if !user_can_admin_group?(auth_user, group)
      halt json_error(200, {
        :error => 'forbidden', 
        :error_description => 'You are not an admin for this group'
      })
    end

    user = User.first({
      :username => params[:username]
    })

    if user.nil?
      halt json_error(200, {
        :error => 'user_not_found', 
        :error_description => 'The specified user was not found'
      })
    end

    user.groups << group
    user.orgs << org
    user.save

    json_response(200, {
      :result => 'success',
      :username => user.username,
      :org => org.name,
      :group => group.slug,
    })
  end

  # Remove a user from a group
  post '/api/users/:username/groups/remove' do
    auth_user = validate_access_token params[:access_token]
    if params[:org].nil?
      halt json_error(200, {
        :error => 'missing_input',
        :error_description => 'Parameter \'org\' is required'
      })
    end

    org = Org.first(:name => params[:org])
    if org.nil?
      halt json_error(200, {
        :error => 'not_found',
        :error_description => 'The organization was not found'
      })
    end

    group = Group.first :irc_channel => "##{params[:group]}", :org => org
    if group.nil?
      halt json_error(200, {
        :error => 'group_not_found', 
        :error_description => 'The specified group was not found'
      })
    end

    if !user_can_admin_group?(auth_user, group)
      halt json_error(200, {
        :error => 'forbidden', 
        :error_description => 'You are not an admin for this group'
      })
    end

    user = org.users.first({
      :username => params[:username]
    })

    if user.nil?
      halt json_error(200, {
        :error => 'user_not_found', 
        :error_description => 'The specified user was not found in the group'
      })
    end

    user.groups -= group
    user.save

    json_response(200, {
      :result => 'success',
      :username => user.username,
      :org => org.name,
      :group => group.slug,
    })
  end

  # Create a new user, optionally adding them to a group at the same time
  # TODO: add :org param
  post '/api/orgs/:org/users' do
    auth_user = validate_access_token params[:access_token]

    if params[:org].nil?
      halt json_error(200, {
        :error => 'missing_input',
        :error_description => 'Parameter \'org\' is required'
      })
    end

    org = Org.first(:name => params[:org])
    if org.nil?
      halt json_error(200, {
        :error => 'not_found',
        :error_description => 'The organization was not found'
      })
    end

    if !user_can_admin_org?(auth_user, org)
      halt json_error(200, {
        :error => 'forbidden',
        :error_description => 'Only organization admins can add users'
      })
    end

    user = User.first({
      :username => params[:username]
    })

    # Support adding this user directly to a group upon creation, optionally
    group = Group.first :irc_channel => "##{params[:group]}", :org => org

    if group && !user_can_admin_group?(auth_user, group)
      halt json_error(200, {
        :error => 'forbidden', 
        :error_description => 'You are not an admin for this group'
      })
    end

    if user.nil?
      user_org = Org.create({
        :name => params[:username]
      })
      user = User.create({
        :username => params[:username],
        :email => params[:email],
        :github_username => params[:github_username],
        :github_email => params[:github_email],
        :gitlab_email => params[:gitlab_email],
        :gitlab_username => params[:gitlab_username],
        :gitlab_user_id => params[:gitlab_user_id].to_i,
        :nicks => params[:nicks],
        :created_at => Time.now,
      })
      OrgUser.create({
        :user => user,
        :org => user_org,
        :is_admin => true
      })
      user.groups = [group] unless group.nil?
      user.orgs << group.org unless group.nil?
      user.save
      status = 'created'
      user
    else
      user.groups << group unless group.nil?
      user.orgs << group.org unless group.nil?
      user.save
      status = 'updated'
    end

    json_response(200, {
      :result => 'success',
      :status => status,
      :username => user.username,
    })
  end


end
