class Controller < Sinatra::Base
  before do 

  end

  get '/?' do
    erb :index
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
    puts params

    group = Group.first :token => params[:token]

    if group.nil?
      return json_error(200, {:error => 'group_not_found', :error_description => 'No group found for the token provided'})
    end

    user = User.first_or_create({
      :account_id => group.account_id, 
      :username => params[:username]
    }, {
      :email => params[:email],
      :github_username => params[:github_username],
      :github_email => params[:github_email],
      :gitlab_email => params[:gitlab_email],
      :gitlab_username => params[:gitlab_username],
      :gitlab_user_id => (params[:gitlab_user_id] ? params[:gitlab_user_id] : 0),
      :created_at => Time.now
    })

    report = Report.current_report(group)

    entry = report.create_entry :user => user, :type => params[:type], :message => params[:message]

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
  end


=begin
  `POST /api/report/remove`

  * token - The token corresponding to the group
  * username - The username sending the report
  * message - The text of the report

  Remove a report. Only entries from an open report can be removed.
=end
  post '/api/report/remove' do
    puts params

    group = Group.first :token => params[:token]

    if group.nil?
      return json_error(200, {:error => 'group_not_found', :error_description => 'No group found for the token provided'})
    end

    user = User.first :account_id => group.account_id, :username => params[:username]

    if user.nil?
      return json_error(200, {:error => 'user_not_found', :error_description => "No user was found for username \"#{params[:username]}\"", :error_username => params[:username]})
    end

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

  # Handles all Github hooks http://developer.github.com/v3/repos/hooks/
  # Create a hook:
  # curly -H "Authorization: Bearer XXXX" https://api.github.com/repos/USER/REPO/hooks -d '{"name":"web","active":true,"events":["commit_comment","create","delete","download","follow","fork","fork_apply","gist","gollum","issue_comment","issues","member","public","pull_request","pull_request_review_comment","push","status","team_add","watch"],"config":{"url":"https://status-report.geoloqi.com/hook/github?token=XXXX","content_type":"json"}}' -H "Content-type: application/json"

  post '/hook/github' do
    event = env['HTTP_X_GITHUB_EVENT']

    if event.nil?
      return json_error(400, {
        error: 'missing_type',
        error_description: 'Expecting an X-Github-Event HTTP header but none was present'
      })
    end

    if params['payload']
      body = params['payload']
    else
      body = request.body.read
    end

    begin
      json = JSON.parse(body)
    rescue => e
      return json_error(400, {
        error: 'bad_request',
        error_description: e
      })
    end

    if params[:token]
      group = Group.first :github_token => params[:token]
    end

    if group.nil?
      return json_error(403, {
        error: 'forbidden',
        error_description: "No group found for token: #{params[:token]}"
      })
    end

    commits = Commit.create_from_payload group, event, json

    if commits.nil?
      puts "-======================================-"
      puts "No entry found for payload"
      jj json
      return json_response 200, {result: "no_data"}
    end

    if !commits.is_a? Array
      commits = [commits]
    end

    commits.each do |commit|
      if commit.irc_message
        begin
          RestClient.post "#{SiteConfig[:zenircbot_url]}#{URI.encode_www_form_component group.irc_channel}", :message => commit.irc_message
        rescue => e
          puts "Exception!"
          puts e
        end
      end
    end

    json_response 200, {result: "ok"}
  end

# Old Github post hook
=begin
  post '/hooks/github' do
    payload = JSON.parse(params[:payload])

    if params[:github_token]
      group = Group.first :github_token => params[:github_token]
    else
      # Hack because I forgot to set up the github hook with the token and need to write a script to clean it up later
      group = Group.get 1
    end

    if group.nil?
      return json_error(200, {:error => 'group_not_found', :error_description => 'No group found for the token provided'})
    end

    # Look for a matching project by the repo URL in the payload
    repo = Repo.first_or_create(:link => payload["repository"]["url"], :group => group)
    if repo
      payload["commits"].each do |commit|
        puts commit.inspect
        # Attempt to map the commit to a user account. Will return nil if not found
        user = User.first :account_id => group.account_id, :github_email => commit["author"]["email"]
        Commit.create(
          :repo => repo,
          :link => commit["url"],
          :text => commit["message"],
          :date => Time.parse(commit["timestamp"]),
          :user_name => commit["author"]["name"],
          :user_email => commit["author"]["email"],
          :user => user
        )
      end
    end
    json_response 200, {:result => 'ok'}
  end
=end

  # Gitlab post-receive hook
  post '/hook/gitlab/:token' do
    payload = JSON.parse(env['rack.input'].read)
    puts payload

    group = Group.first :github_token => params[:token]

    if group.nil?
      return json_error(200, {:error => 'group_not_found', :error_description => 'No group found for the token provided'})
    end

    # Look for a matching project by the repo URL in the payload
    if payload["repository"]["homepage"]
      link = payload["repository"]["homepage"]
    else
      link = payload["repository"]["url"]
    end

    repo = Repo.first_or_create(:link => link, :group => group)
    if repo
      payload["commits"].each do |commit|
        puts commit.inspect
        # Attempt to map the commit to a user account. Will return nil if not found
        user = User.first :account_id => group.account_id, :gitlab_email => commit["author"]["email"]
        # Try searching for their github email instead
        if user.nil?
          user = User.first :account_id => group.account_id, :github_email => commit["author"]["email"]
        end
        Commit.create(
          :repo => repo,
          :link => commit["url"],
          :text => commit["message"],
          :date => Time.parse(commit["timestamp"]),
          :user_name => commit["author"]["name"],
          :user_email => commit["author"]["email"],
          :user => user
        )
      end

      user = User.first :account_id => group.account_id, :gitlab_user_id => payload['user_id']
      if user
        event = Commit.create({
          type: 'push',
          repo: repo,
          user: user,
          date: Time.now,
          text: "#{user.username} pushed #{payload["commits"].length} commits"
        })
        if event.irc_message
          begin
            RestClient.post "#{SiteConfig[:zenircbot_url]}#{URI.encode_www_form_component group.irc_channel}", :message => event.irc_message
          rescue => e
            puts "Exception!"
            puts e
          end
        end
      end
    end
    json_response 200, {:result => 'ok'}
  end


  def json_error(code, data)
    return [code, {
        'Content-Type' => 'application/json;charset=UTF-8',
        'Cache-Control' => 'no-store'
      }, 
      data.to_json]
  end

  def json_response(code, data)
    return [code, {
        'Content-Type' => 'application/json;charset=UTF-8',
        'Cache-Control' => 'no-store'
      }, 
      data.to_json]
  end
 
end
