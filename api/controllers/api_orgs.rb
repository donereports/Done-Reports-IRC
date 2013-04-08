class Controller < Sinatra::Base

  get '/api/orgs/:org/servers' do
    auth_user = validate_access_token params[:access_token]
    org = validate_org_admin! auth_user, params[:org]

    servers = []
    org.ircservers.each do |server|
      servers << {
        :hostname => server.hostname,
        :port => server.port,
        :ssl => server.ssl,
        :password => server.server_password,
        :global => false
      }
    end
    Ircserver.all(:global => true).each do |server|
      servers << {
        :hostname => server.hostname,
        :port => server.port,
        :ssl => server.ssl,
        :password => server.server_password,
        :global => true
      }
    end

    json_response(200, {
      :servers => servers
    })
  end

  post '/api/orgs/:org/servers' do
    auth_user = validate_access_token params[:access_token]
    org = validate_org_admin! auth_user, params[:org]

    # Check for required parameters
    [:hostname, :port, :ssl].each do |param|
      if params[param].nil?
        halt json_error(200, {
          :error => 'missing_input',
          :error_description => "Parameter '#{param.to_s}' is required"
        })
      end
    end

    # Check for duplicate hostname
    server = org.ircservers.first(:hostname => params[:hostname])

    unless server.nil?
      halt json_error(200, {
        :error => 'already_exists',
        :error_description => 'A server already exists with the specified hostname'
      })
    end

    server = Ircserver.create({
      :org => org,
      :hostname => params[:hostname],
      :port => params[:port],
      :ssl => params[:ssl],
      :server_password => params[:password]
    })

    data = {
      :hostname => server.hostname,
      :port => server.port,
      :ssl => server.ssl,
      :password => server.server_password,
      :global => false
    }

    json_response(200, {
      :server => data
    })
  end

end
