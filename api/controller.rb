class Controller < Sinatra::Base

  get '/?' do
    erb :index
  end

  def json_error(code, data)
    if params[:callback]
      response = "#{params[:callback]}(#{data.to_json})"
    else
      response = data.to_json
    end

    return [code, {
        'Content-Type' => 'application/json;charset=UTF-8',
        'Cache-Control' => 'no-store',
        'Access-Control-Allow-Origin' => '*',
      }, 
      response]
  end

  def json_response(code, data)
    if params[:callback]
      response = "#{params[:callback]}(#{data.to_json})"
    else
      response = data.to_json
    end

    return [code, {
        'Content-Type' => 'application/json;charset=UTF-8',
        'Cache-Control' => 'no-store',
        'Access-Control-Allow-Origin' => '*',
      }, 
      response]
  end
 
end
