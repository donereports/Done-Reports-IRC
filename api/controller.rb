class Controller < Sinatra::Base
  before do 

  end

  get '/?' do
    erb :index
  end


 
end
