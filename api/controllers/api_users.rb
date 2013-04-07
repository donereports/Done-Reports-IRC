class Controller < Sinatra::Base

  # Retrieve all users for all orgs, including the list of channels each user is in
  # Does not include deactivated users
  get '/api/users' do
    auth_user = validate_access_token params[:access_token]

    users = []
    auth_user.orgs.users.all(:active => true).each do |user|
      users << {
        :username => user.username,
        :avatar_url => user.avatar_url,
        :email => user.email,
        :nicks => user.nicks,
        :active => user.active,
        :groups => user.groups.all.collect{|group|
          # Only returns groups from organizations the authenticating user has access to
          org_user = auth_user.org_user.first(:org => group.org)
          if org_user.nil?
            nil
          else
            {
              :org => group.org.name,
              :slug => group.slug,
              :name => group.name,
              :channel => group.irc_channel,
            }
          end
        }.compact
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
        :org_name => group.org.name,
        :name => group.name,
        :channel => group.irc_channel,
        :timezone => group.due_timezone,
      }
    }

    json_response(200, {
      :username => user.username,
      :avatar_url => user.avatar_url,
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
