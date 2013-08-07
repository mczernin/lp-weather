require 'sinatra'
require 'json'
require './weather'
require 'date'


# Returns today's edition of weather.
# Excpects a human-friendly address, a location (probably a lat-long), and optionally a scale.
get '/edition/' do
  success = false
  err_count = 0
  
  scale = params["scale"].nil? ? 'celsius' : params["scale"]
  
  if params["test"]
    etag Digest::MD5.hexdigest("test"+Date.ordinal.to_s)
    @forecast = Weather.fetch_data('location', 'address', 'celsius', true)
  else

    # There is one subscriber who has no location (confusingly). In this case use the address as the location. This will work too.
    if params["location"] && params["location"] !=',' && params["location"] !=''
      location = params["location"]
    else
      if params["address"]
        location = params["address"]
      else 
        return 500, 'No address provided'
      end
    end
    
    # Older subscribers will not have set up an address. We can use the location feild as the address field in this case.
    if params["address"]
      address = params["address"]
    else
      address = params["location"]
    end

    etag Digest::MD5.hexdigest(location+scale+Time.now.strftime('%l%p%d%b%Y%Z'))

    begin
      # Get the forecast
      @forecast = Weather.fetch_data(location, address, scale)
      success = true
    rescue NetworkError => e
      return 502, "Network Error: #{e}"
    rescue PermanentError => e
      return 500, "Permanent Error: #{e}"
    end
  end

  erb :weather
end

post '/validate_config/' do
  content_type :json
  response = {}
  response[:errors] = []
  config = JSON.parse(params[:config])
  
  if ['celsius', 'farenheit'].include? config['scale']
    response[:valid] = true
  else
    response[:valid] = false
    response[:errors] << "'#{config['scale']}' is not a valid scale"
  end

  response.to_json
end


get '/sample/' do
  @forecast = Weather::SAMPLE_DATA
  erb :weather
end


# users sent here from BERG Cloud to pick the location for their forcast
get '/configure/' do
  # Barf if the return url is not BERG
  return_uri = URI(params[:return_url])
  return 403 unless return_uri.host.end_with?('bergcloud.com')
  @return_url = params[:return_url] 
  
  # Barf if the error url is not BERG
  error_uri = URI(params[:error_url])
  return 403 unless error_uri.host.end_with?('bergcloud.com')
  @error_url = params[:error_url]
  
  if @return_url.nil?
    if @error_url.nil?
      raise Exception, 'No return URL was provided'
    else
      redirect @error_url
    end
  else
    erb :location_picker
  end
end

post '/configure/' do
  # Barf if the error url is not BERG
  error_uri = URI(params[:error_url])
  return 403 unless error_uri.host.end_with?('bergcloud.com')
  @error_url = params[:error_url]
  
  # Barf if the return url is not BERG
  return_uri = URI(params[:return_url])
  return 403 unless return_uri.host.end_with?('bergcloud.com')
  @return_url = params[:return_url]
  
  
  if @return_url.nil?
    erb :something_broke
  else 
    
    location="#{params['latitude']},#{params['longitude']}"
    
    if params['latitude'].nil? || params['longitude'].nil? || params['address'].nil?
      @error = "Please select a location"
    else 
      
      # return user to address provided by BERGCloud
      redirect "#{@return_url}?config[location]=#{location}&config[address]=#{params['address']}" 
    end
  end
end

error do
  erb :error
end

not_found do
  erb :not_found
end
