class Controller < Sinatra::Base

  def validate_access_token(token)
    if token == "" or token == nil
      halt json_error(200, {:error => 'access_token_required', :error_description => 'Must provide a token'})
    end

    begin
      tokenInfo = JWT.decode(token, SiteConfig.token_secret)
    rescue
      halt json_error(200, {:error => 'invalid_token', :error_description => 'The token provided could not be validated'})
    end

    user = User.first :id => tokenInfo[:user_id], :active => 1

    if user.nil?
      halt json_error(200, {:error => 'user_not_found', :error_description => 'The user account is not active'})
    end

    user
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
        halt json_error(200, {:error => 'user_not_found'})
      end

      token = JWT.encode({:user_id => user.id}, SiteConfig.token_secret)

      json_response(200, {
        :username => user.username,
        :token => token
      })
    else
      redirect "https://github.com/login/oauth/authorize?client_id=#{SiteConfig.github_id}&state=#{SecureRandom.urlsafe_base64(20)}"
    end
  end

  post '/api/user/new' do
    auth_user = validate_access_token params[:access_token]
    group = Group.first :irc_channel => params[:channel], :account => auth_user.account

    if group.nil?
      halt json_error(200, {:error => 'group_not_found', :error_description => 'The specified group was not found'})
    end

    user = User.first({
      :account_id => group.account_id, 
      :username => params[:username]
    })

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
        :groups => [group]
      })
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
      user.groups << group
      user.save
      status = 'updated'
    end

    json_response(200, {
      :result => 'success',
      :status => status,
      :username => user.username,
    })
  end

  post '/api/user/deactivate' do
    group = load_group params[:token]

    user = User.first({
      :account_id => group.account_id, 
      :username => params[:username]
    })

    if user.nil?
      json_error(200, {
        :error => 'user_not_found',
        :error_description => 'No user was found with the specified username'
      })
    else
      user.active = false
      user.save
    end

    json_response(200, {
      :result => 'success',
      :status => 'deactivated',
      :username => user.username
    })
  end

end
