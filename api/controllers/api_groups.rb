class Controller < Sinatra::Base

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

  # Retrieve information about a group
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
      :org_name => org.name,
      :name => group.name,
      :channel => group.irc_channel,
      :timezone => group.due_timezone,
      :time => time,
      :members => group.users.length,
      :is_admin => user_can_admin_group?(auth_user, group)
    })
  end

  # Create a new group under the given organization
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

  # Get a list of all users in a group
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

end
