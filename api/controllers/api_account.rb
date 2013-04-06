class Controller < Sinatra::Base

  def validate_account_access(token)
    if token != SiteConfig.supertoken
      halt json_error(200, {
        :error => 'access_denied'
      })
    end
  end

  # Create a new account and user
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

    account = Account.create({
      :name => params[:name]
    })

    user = User.first({
      :github_username => params[:github_username]
    })

    unless user.nil?
      halt json_error(200, {
        :error => 'user_already_exists',
        :error_description => 'The specified user already has an account'
      })
    end

    user = User.create({
      :account => account,
      :username => params[:github_username], # This can safely be changed later
      :email => params[:email],
      :github_username => params[:github_username], # This must be globally unique
      :github_email => params[:github_email],
      :created_at => Time.now
    })

    access_token = generate_access_token user

    json_response(200, {
      :username => user.username,
      :access_token => access_token
    })
  end

end
