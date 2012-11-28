class Controller < Sinatra::Base
  before do 

  end

  get '/?' do
    erb :index
  end

=begin
  `POST /api/report/new`

  * token - The token corresponding to the group
  * username - The username sending the report
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

    user = User.first :account_id => group.account_id, :username => params[:username]

    if user.nil?
      return json_error(200, {:error => 'user_not_found', :error_description => "No user was found for username \"#{params[:username]}\"", :error_username => params[:username]})
    end

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
