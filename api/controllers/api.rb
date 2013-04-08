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

  def validate_org_admin!(user, org_name)
    org = Org.first(:name => org_name)
    if org.nil?
      halt json_error(200, {
        :error => 'not_found',
        :error_description => 'The organization was not found'
      })
    end

    if !user_can_admin_org?(user, org)
      halt json_error(200, {
        :error => 'forbidden',
        :error_description => 'Only organization admins can do that'
      })
    end

    org
  end

  def validate_org_access!(user, org_name)
    org = Org.first(:name => org_name)
    if org.nil?
      halt json_error(200, {
        :error => 'not_found',
        :error_description => 'The organization was not found'
      })
    end

    org_user = user.org_user.first(:org => org)
    if org_user.nil?
      halt json_error(200, {
        :error => 'forbidden',
        :error_description => 'The user does not have access to this organization'
      })
    end

    org
  end

  def user_can_admin_group?(user, group)
    return true if user_can_admin_org?(user, group.org)
    link = user.group_user.first(:group => group)
    return false if link.nil?
    return link.is_admin == true
  end

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

    orgs = auth_user.org_user.collect{|link|
      {
        :name => link.org.name,
        :is_admin => link.is_admin
      }
    }

    json_response(200, {
      :username => auth_user.username,
      :email => auth_user.email,
      :orgs => orgs
    })
  end

end
