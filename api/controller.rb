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
      return json_error(200, {:error => 'user_not_found', :error_description => 'No user was found for the given username'})
    end

    report = Report.current_report(group)

    entry = ReportEntry.create :report => report, :user => user, :date => Time.now, :type => params[:type], :message => params[:message]

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
