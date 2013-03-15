class Controller < Sinatra::Base

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

end
