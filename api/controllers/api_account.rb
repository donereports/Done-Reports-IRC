class Controller < Sinatra::Base

  def validate_account_access(token)
    if token != SiteConfig.supertoken
      halt json_error(200, {
        :error => 'access_denied'
      })
    end
  end

  # Allows the website to obtain a token for a user without going through Github auth
  get '/auth/assertion' do
    validate_account_access params[:supertoken]

    if params[:username] == nil || params[:username] == ""
      halt json_error(200, {
        :error => 'missing_username',
        :error_description => 'Parameter \'username\' is required'
      })
    end

    user = User.first :github_username => params[:username]

    if user.nil?
      halt json_error(200, {
        :error => 'user_not_found',
        :error_description => 'No account was found for the username provided'
      })
    end

    token = generate_access_token user
    if params[:redirect]
      uri = URI.parse params[:redirect]
      uri.query = "username=#{user.username}&access_token=#{token}"
      redirect uri.to_s
    else
      json_response(200, {
        :username => user.username,
        :access_token => token
      })
    end
  end

  get '/autocomplete/users' do
    validate_account_access params[:supertoken]

    if params[:input] == nil || params[:input] == ''
      halt json_error(200, {
        :error => 'missing_input',
        :error_description => 'No input provided'
      })
    end

    users = []

    User.all(:active => true, :username.like => "#{params[:input]}%").each do |user|
      users << {
        :username => user.username,
        :avatar_url => user.avatar_url
      }
    end

    json_response(200, {
      :users => users
    })
  end

  get '/autocomplete/user/:username' do |username|
    validate_account_access params[:supertoken]

    user = User.first(:username => username)

    if user.nil?
      json_response(200, {
        :error => 'user_not_found'
      })
    else
      json_response(200, {
        :username => user.username,
        :email => user.email,
        :nicks => user.nicks,
        :github_username => user.github_username,
        :github_email => user.github_email
      })
    end
  end

  # Create a new organization and user
  post '/accounts' do
    validate_account_access params[:supertoken]

    if params[:name] == nil || params[:name] == ""
      halt json_error(200, {
        :error => 'missing_name',
        :error_description => 'Parameter \'name\' is required'
      })
    end

    if params[:github_username] == nil || params[:github_username] == ""
      halt json_error(200, {
        :error => 'missing_github_username',
        :error_description => 'Parameter \'github_username\' is required'
      })
    end

    user = User.first({
      :github_username => params[:github_username]
    })

    unless user.nil?
      halt json_error(200, {
        :error => 'user_already_exists',
        :error_description => 'The specified user already has an account'
      })
    end

    org = Org.create({
      :name => params[:name]
    })

    user = User.create({
      :username => params[:github_username],
      :email => params[:email],
      :github_username => params[:github_username], # This must be globally unique
      :github_email => params[:github_email],
      :created_at => Time.now,
    })
    user.org_user << {:org => org, :is_admin => true}
    user.save

    access_token = generate_access_token user

    json_response(200, {
      :username => user.username,
      :access_token => access_token
    })
  end

end
