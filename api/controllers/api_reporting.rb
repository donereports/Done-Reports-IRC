class Controller < Sinatra::Base

  def load_group(token)
    if token == "" or token == nil
      halt json_error(200, {:error => 'token_required', :error_description => 'Must provide a token'})
    end

    group = Group.first :token => token

    if group.nil?
      halt json_error(200, {:error => 'group_not_found', :error_description => 'No group found for the token provided'})
    end

    group
  end

  def load_user(username, group)
    user = group.users.first :username => username

    if user.nil?
      # Check if this is a real account or not
      test = User.first :username => username
      if test.nil?
        halt json_error(200, {:error => 'user_not_found', :error_description => "No user was found for username \"#{username}\"", :error_username => username})
      else
        halt json_error(200, {:error => 'user_not_in_group', :error_description => "Sorry, \"#{username}\" is not in the group", :error_username => username})
      end
    end

    if user.active == false
      halt json_error(200, {:error => 'user_disabled', :error_description => "The user account for \"#{username}\" is disabled", :error_username => username})
    end

    user
  end

  def load_server(token)
    if token == "" or token == nil
      halt json_error(200, {:error => 'token_required', :error_description => 'Must provide a token'})
    end

    server = Ircserver.first :zenircbot_configtoken => token

    if server.nil?
      halt json_error(200, {:error => 'not_found', :error_description => 'No server found for the token provided'})
    end

    server
  end

=begin
  `POST /api/report/new`

  * token - The token corresponding to the group
  * user data - The user sending the report
  *   - username
  *   - email
  *   - github_email
  *   - github_username
  * type - past, future, blocking, hero, unknown
  * message - The text of the report

  Post a new report. Automatically associated with the current open report for the group.
=end
  post '/api/report/new' do
    group = load_group params[:token]

    user = load_user params[:username], group

    report = Report.current_report(group)

    entry = report.create_entry :user => user, :type => params[:type], :message => params[:message]

    if entry.id
      json_response 200, {
        :group => {
          :name => group.name
        }, 
        :report => {
          :report_id => report.id, 
          :date_started => report.date_started
        },
        :entry => {
          :entry_id => entry.id,
          :username => entry.user.username,
          :date => entry.date,
          :type => entry.type,
          :message => entry.message
        }
      }
    else
      json_error 200, {
        :error => 'unknown_error',
        :error_description => 'There was a problem saving the entry'
      }
    end
  end


=begin
  `POST /api/report/remove`

  * token - The token corresponding to the group
  * username - The username sending the report
  * message - The text of the report

  Remove a report. Only entries from an open report can be removed.
=end
  post '/api/report/remove' do
    group = load_group params[:token]

    user = load_user params[:username], group

    report = Report.current_report(group)

    entry = Entry.first :report => report, :user => user, :message => params[:message]

    if entry 
      entry.destroy
      json_response(200, {
        :result => 'success',
        :message => 'Entry was successfully deleted'
      })
    else
      json_error(200, {
        :error => 'entry_not_found',
        :error_description => 'No entry was found with the provided text'
      })
    end
  end

  # Returns a JSON config block for the group to be loaded into the IRC bot config
  get '/api/group/config' do
    group = load_group params[:token]

    data = {
      channel: group.irc_channel,
      timezone: group.due_timezone,
      users: []
    }

    group.users(:active => 1).each do |user|
      user_info = {
        username: user.username,
        nicks: (user.nicks ? user.nicks.split(',') : [])
      }
      data[:users] << user_info
    end

    json_response(200, data)
  end

  get '/api/bot/config' do
    server = load_server params[:token]

    data = {
      :groups => []
    }

    server.groups.each do |group|
      groupInfo = {
        channel: group.irc_channel,
        timezone: group.due_timezone,
        token: group.token,
        users: []
      }

      group.users(:active => 1).each do |user|
        userInfo = {
          username: user.username,
          nicks: (user.nicks ? user.nicks.split(',') : [])
        }
        groupInfo[:users] << userInfo
      end

      data[:groups] << groupInfo
    end

    json_response 200, data
  end

end
