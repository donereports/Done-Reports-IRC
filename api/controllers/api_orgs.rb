class Controller < Sinatra::Base

  get '/api/orgs/:org/servers' do
    auth_user = validate_access_token params[:access_token]
    org = validate_org_admin! auth_user, params[:org]



  end

end
