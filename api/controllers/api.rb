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

  def user_is_group_admin?(user, group)
    link = user.group_user.first(:group => group)
    return false if link.nil?
    return link.is_admin == true
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

      token = JWT.encode({:user_id => user.id}, SiteConfig.token_secret)

      # TODO: If a redirect parameter is present, redirect to the site with the token in the URL instead
      json_response(200, {
        :username => user.username,
        :token => token
      })
    else
      redirect "https://github.com/login/oauth/authorize?client_id=#{SiteConfig.github_id}&state=#{SecureRandom.urlsafe_base64(20)}"
    end
  end

  # Retrieve all users in the account, including the list of channels each user is in
  # Does not include deactivated users
  get '/api/users' do
    auth_user = validate_access_token params[:access_token]

    users = []
    auth_user.account.users.all(:active => true).each do |user|
      users << {
        :username => user.username,
        :email => user.email,
        :groups => user.groups.collect {|group|
          {
            :slug => group.slug,
            :name => group.name,
            :channel => group.irc_channel,
          }
        }
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
      can_edit = true if user_is_group_admin? auth_user, group
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
    group = Group.first :irc_channel => "##{params[:group]}", :account => auth_user.account

    if group.nil?
      halt json_error(200, {
        :error => 'group_not_found', 
        :error_description => 'The specified group was not found'
      })
    end

    if !user_is_group_admin?(auth_user, group)
      halt json_error(200, {
        :error => 'forbidden', 
        :error_description => 'You are not an admin for this group'
      })
    end

    user = User.first({
      :account_id => group.account_id, 
      :username => params[:username]
    })

    if user.nil?
      halt json_error(200, {
        :error => 'user_not_found', 
        :error_description => 'The specified user was not found'
      })
    end

    user.groups << group
    user.save

    groups = user.groups.collect {|group|
      {
        :slug => group.slug,
        :name => group.name,
        :channel => group.irc_channel,
        :timezone => group.due_timezone,
      }
    }

    json_response(200, {
      :result => 'success',
      :username => user.username,
      :groups => groups,
    })
  end

  post '/api/users/:username/groups/:channel/remove' do
    auth_user = validate_access_token params[:access_token]
    group = Group.first :irc_channel => "##{params[:group]}", :account => auth_user.account

    if group.nil?
      halt json_error(200, {
        :error => 'group_not_found', 
        :error_description => 'The specified group was not found'
      })
    end

    if !user_is_group_admin?(auth_user, group)
      halt json_error(200, {
        :error => 'forbidden', 
        :error_description => 'You are not an admin for this group'
      })
    end

    user = User.first({
      :account_id => group.account_id, 
      :username => params[:username]
    })

    if user.nil?
      halt json_error(200, {
        :error => 'user_not_found', 
        :error_description => 'The specified user was not found'
      })
    end

    user.groups -= group
    user.save

    groups = user.groups.collect {|group|
      {
        :name => group.name,
        :channel => group.irc_channel,
        :timezone => group.due_timezone,
      }
    }

    json_response(200, {
      :result => 'success',
      :username => user.username,
      :groups => groups,
    })
  end

  # Create a new user account, optionally adding them to a group at the same time
  post '/api/users' do
    auth_user = validate_access_token params[:access_token]

    user = User.first({
      :account_id => auth_user.account_id,
      :username => params[:username]
    })

    # Support adding this user directly to a group upon creation, optionally
    group = Group.first :irc_channel => "##{params[:group]}", :account => auth_user.account

    if !user_is_group_admin?(auth_user, group)
      halt json_error(200, {
        :error => 'forbidden', 
        :error_description => 'You are not an admin for this group'
      })
    end

    if user.nil?
      user = User.create({
        :account_id => group.account_id, 
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
      user.groups = [group] unless group.nil?
      user.save
      status = 'created'
      user
    else
      user.username = params[:username]
      user.email = params[:email]
      user.github_username = params[:github_username]
      user.github_email = params[:github_email]
      user.gitlab_email = params[:gitlab_email]
      user.gitlab_username = params[:gitlab_username]
      user.gitlab_user_id = params[:gitlab_user_id].to_i
      user.nicks = params[:nicks]
      user.groups << group unless group.nil?
      user.save
      status = 'updated'
    end

    json_response(200, {
      :result => 'success',
      :status => status,
      :username => user.username,
    })
  end

  # Deactivate a user account
  # Can only deactivate a user account that belongs to a group you administer
  post '/api/users/:username/deactivate' do
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
    can_deactivate = false
    user.groups.each do |group|
      can_deactivate = true if user_is_group_admin? auth_user, group
    end

    if !can_deactivate
      halt json_error(200, {
        :error => 'forbidden',
        :error_description => 'You can only deactivate a user if you administer at least one of the groups the user belongs to'
      })
    end

    user.active = false
    user.save

    json_response(200, {
      :result => 'success',
      :status => 'deactivated',
      :username => user.username
    })
  end

end
