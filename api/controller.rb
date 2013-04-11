class Controller < Sinatra::Base

  get '/?' do
    redirect 'http://donereports.com/'
  end

  def array_from_input(input)
    return nil if input.nil?

    if input.class == String
      input.split(',')
    elsif input.class == Array
      input
    else
      input
    end
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
