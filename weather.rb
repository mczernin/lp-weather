require 'rest-client'
require 'yaml'


class Weather
  CONTENT_URL = "http://free.worldweatheronline.com/feed/weather.ashx?"
  
  # Wishful thinking :(
  SAMPLE_DATA = {:location => "London", :address=>"London", :weather_image => "sunny", :weather_description => "Sunny", :min => 20, :max => 24, :units => "C"}
  
  def self.api_key
    
    # If there is an env variable with the key, use that, else look in config.yml
    if ENV['WEATHER_KEY'] != nil
      return ENV['WEATHER_KEY']
    else
      config = YAML.load_file('./config.yml')
      return config['weather_api_key']
    end
  end
  
  def self.fetch_data location, address, scale, is_test=false
    return SAMPLE_DATA if is_test
    url_location = ERB::Util::url_encode(location)
    
    begin 
      weather_doc = RestClient.get("#{CONTENT_URL}query=#{url_location}&format=json&num_of_days=1&key=#{api_key}")
      raise NetworkError, "Could not connect to #{CONTENT_URL}, weather api returned #{weather_doc.code.to_i}" unless weather_doc.code.to_i < 299
      weather_body = JSON.parse(weather_doc)
    rescue JSON::ParserError
      raise NetworkError, "Couldn't parse JSON"
    rescue Timeout::Error
      raise NetworkError, "Timed out when connecting to #{CONTENT_URL}"
    rescue RestClient::ServiceUnavailable
      raise NetworkError, "Could not connect to #{CONTENT_URL}"
    end

    forecasts = []

    if weather_body.nil?
      raise "Parse error. Could not find weather items from #{CONTENT_URL}"
    end

    begin
      if scale == 'fahrenheit'
        min = 'tempMinF'
        max = 'tempMaxF'
        units = 'F'
        
      #Default to celsius
      else
        min = 'tempMinC'
        max = 'tempMaxC'
        units = 'C'
      end

      weather_body['data']['weather'].each do |element| 
        forecasts = { 
          :location => location,
          :address => address,
          :weather_image => extract_condition(element['weatherCode']),
          :weather_description => element['weatherDesc'][0]['value'],
          :min => element[min],
          :max => element[max],
          :units => units
        }

      end
    rescue
      raise PermanentError, "Parse error. Could not find weather items from #{CONTENT_URL}"
    end

    raise PermanentError, "Parse error. No elements were extracted from the weather forecast" if forecasts == []

    forecasts

  end

  def self.extract_condition key

    # Mapping from weather integers to image names.
    weather_types_mapping = {
      # Fog    
      "248" => "fog",
      "260" => "fog",

      # Heavy cloud
      "122" => "heavy_cloud",

      # Heavy rain
      "302" => "heavy_rain",
      "308" => "heavy_rain",
      "359" => "heavy_rain",

      # Heavy showers
      "299" => "heavy_showers",
      "305" => "heavy_showers",
      "356" => "heavy_showers",

      # Heavy snow showers
      "335" => "heavy_snow_showers",
      "371" => "heavy_snow_showers",
      "395" => "heavy_snow_showers",

      # Heavy snow
      "230" => "heavy_snow",
      "329" => "heavy_snow",
      "332" => "heavy_snow",
      "338" => "heavy_snow",

      # Light cloud
      "119" => "light_cloud",

      # Light rain
      "266" => "light_rain",
      "293" => "light_rain",
      "296" => "light_rain",


      # Light showers
      "176" => "light_showers",
      "263" => "light_showers",
      "353" => "light_showers",

      # Light snow showers
      "323" => "light_snow_showers",
      "326" => "light_snow_showers",
      "368" => "light_snow_showers",

      # Light snow
      "227" => "light_snow",
      "320" => "light_snow",

      # Mist
      "143" => "mist",

      # Sleet showers
      "179" => "sleet_showers",
      "362" => "sleet_showers",
      "365" => "sleet_showers",
      "374" => "sleet_showers",

      # Sleet
      "182" => "sleet",
      "185" => "sleet",
      "281" => "sleet",
      "284" => "sleet",
      "311" => "sleet",
      "314" => "sleet",
      "317" => "sleet",
      "350" => "sleet",
      "377" => "sleet",

      "116" => "sunny_intervals",
      "113" => "sunny",

      #Thunder shower
      "200" => "thundery_showers",
      "386" => "thundery_showers",
      "392" => "thundery_showers",

      #Thunder
      "389" => "thunder"
    }

    weather_types_mapping[key]

  end



  # Check that the location that has been given by the user is one worldweatheronline understands
  def self.location_is_valid location

    validation_url = "http://www.worldweatheronline.com/feed/search.ashx?query=#{location}&num_of_results=1&format=json&key=#{Weather::api_key}"

    begin
      weather = RestClient.get(validation_url)
    rescue RestClient::ServiceUnavailable
      raise NetworkError, "ServiceUnavailable was received from #{validation_url}"
    rescue Timeout::Error
      raise NetworkError, "Connection to #{validation_url} timed out!"
    end
    
    begin
      weather_content =  JSON.parse(weather)
    rescue 
      raise PermanentError, 'there was an error parsing the JSON'
    end
    
    if weather_content['search_api'].nil?
      return false
    else
      return true
    end
  end
end

class PermanentError < StandardError; end
class NetworkError < StandardError; end
  
