class Controller < Sinatra::Base

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
  
end
