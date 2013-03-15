class Controller < Sinatra::Base

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

end
