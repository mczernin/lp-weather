require './publication'
require './weather'
require 'rspec'
require 'rack/test'
require 'json'
require 'webmock/rspec'
require 'sinatra/contrib'
config_file './config.yml'

set :environment, :test

describe 'Publication' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  before(:each) do
    WebMock.disable_net_connect!(:allow_localhost => true)
    @location = "W1T 4JZ"
    @address = 'The BT Tower'
    
    @scale = 'celsius'
    @forecast = { 
      :location => @location,
      :address => @address,
      :weather_image => 'sunny',
      :weather_description => 'Sunny',
      :min => '24',
      :max => '28',
      :precip_type => 'rain',
      :precip_probability => '0.3',
      :units => 'C'
    }
  end
  
  # Can't get this to work at all. Keep getting:
  # undefined method `config' for Sinatra::Application:Class (NoMethodError)
  # Time to move on and do something else.
  #describe 'validate_config' do
    #post '/validate_config/', :config => {'scale' => 'celsius'}.to_json
    #p last_response.body
  #end


  describe 'edition' do
   it 'should return html for a get with location, address and scale' do
     Weather.should_receive(:fetch_data).with(@location, @address, @scale).and_return(@forecast)
     get "/edition/?location=#{URI.escape(@location)}&address=#{URI.escape(@address)}&scale=#{@scale}"
     last_response.should be_ok
     
     new_address = @forecast[:address][/([^,]+,?(?:[^,]*))/].gsub(/(.*)( )(.*)/, '\1&nbsp;\3')
     precipitation = (@forecast[:precip_probability].to_f * 100).round().to_s

     # should include location/forecast/etc
     last_response.body.scan(new_address).length.should == 1
     last_response.body.scan("#{@forecast[:weather_image]}.png").length.should == 1
     last_response.body.scan(@forecast[:min]).length.should == 1
     last_response.body.scan(@forecast[:max]).length.should == 1
     last_response.body.scan(@forecast[:precip_type]).length.should == 1
     last_response.body.scan(precipitation).length.should == 1
     
    end

    it 'should use celsius if the scale is omitted' do
      Weather.should_receive(:fetch_data).with(@location, @address, @scale).and_return(@forecast)
      get "/edition/?location=#{URI.escape(@location)}&address=#{URI.escape(@address)}"
      last_response.should be_ok
    end

    # It should throw a 502 after three erroring (with network) calls to fetch_data
    it 'should retry three times before returning a 502 if there is an upstream error' do
      Weather.stub(:fetch_data).and_raise(NetworkError)
      get '/edition/?location=London&address=london'
      last_response.status.should == 502
    end

    it 'should return a 500 after three erroring (with parse) calls to fetch_data' do
      Weather.stub(:fetch_data).and_raise(PermanentError)
      get '/edition/?location=London&address=london'
      last_response.status.should == 500
    end
    
    it 'should set an etag that changes every hour' do
      Weather.stub!(:fetch_data).and_return(@forecast)
      date_one = Time.parse('3rd Feb 2001 04:05:06+03:30')
      date_two = Time.parse('3rd Feb 2001 05:05:06+03:30')
      date_three = Time.parse('3rd Feb 2001 05:10:06+03:30')
      Time.stub(:now).and_return(date_one)
      get '/edition/?location=London&address=london'
      etag_one = last_response.original_headers["ETag"]
      
      Time.stub(:now).and_return(date_two)
      get '/edition/?location=London&address=london'
      etag_two = last_response.original_headers["ETag"]
      
      get '/edition/?location=London&address=london'
      etag_three = last_response.original_headers["ETag"]
      
      Time.stub(:now).and_return(date_three)
      get '/edition/?location=London&address=london'
      etag_four = last_response.original_headers["ETag"]
      
      etag_one.should_not == etag_two
      etag_two.should == etag_three
      etag_four.should == etag_three
    end
    
    it 'should set an etag that changes for different locations' do
      Weather.stub!(:fetch_data).and_return(@forecast)

      get '/edition/?location=york'
      etag_one = last_response.original_headers["ETag"]
      
      get '/edition/?location=manchester'
      etag_two = last_response.original_headers["ETag"]
      
      get '/edition/?location=manchester'
      etag_three = last_response.original_headers["ETag"]

      etag_one.should_not == etag_two
      etag_two.should == etag_three
    end
  end
  
  describe 'get a sample' do
  
    it 'should return some html for get requests to /sample/' do
      get '/sample/'
      address = Weather::SAMPLE_DATA[:address][/([^,]+,?(?:[^,]*))/].gsub(/(.*)( )(.*)/, '\1&nbsp;\3')
      last_response.body.scan(address).length.should == 1
      last_response.body.scan(Weather::SAMPLE_DATA[:weather_description].chomp('.')).length.should == 1
    end
    
  end
  
  describe 'get meta.json' do

    it 'should return json for meta.json' do
      get '/meta.json'
      last_response["Content-Type"].should == "application/json;charset=utf-8"
      json = JSON.parse(last_response.body)
      json["name"].should_not == nil
      json["description"].should_not == nil
      json["delivered_on"].should_not == nil
    end
  
  end


  describe 'get icon' do
  
    it 'should return a png for /icon' do
      get '/icon.png'
      last_response['Content-Type'].should = 'image/png'
    end
    
  end
  
end

describe 'Weather' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end
    
  describe "#fetch_data" do 
    before(:each) do
      @location = "51.5229965,-0.08712990000003629"
      @address = 'The BT Tower'
      @exclude = 'minutely,hourly,flags'

      @scale = 'celsius'
      @units = 'uk'
      
      @weather_url = "https://api.forecast.io/forecast/#{settings.forecast_api_key}/#{URI.escape(@location)}?exclude=#{URI.escape(@exclude)}&units=#{@units}"
      @forecast = { 
        :location => @location,
        :address => @address,
        :weather_image => 'sunny',
        :weather_description => 'Sunny',
        :min => '11',
        :max => '15',
        :precip_type => 'rain',
        :precip_probability => '0.3',
        :units => 'C'
      }
    end
   
    it "should return a weather forecast" do 
    
      file = File.open(File.join( "spec_assets","stub_data.json"), "rb")
      return_content = file.read
      
      stub_request(:get, @weather_url).
        with(:headers => {'Accept'=>'*/*', 'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3', 'User-Agent'=>'Faraday v0.8.8'}).
        to_return(:status => 200, :body => return_content, :headers => {})
 
            
      weather = Weather.fetch_data(@location, @address, @scale)
    
      weather[:location].nil?.should == false
      weather[:weather_description].nil?.should == false
      weather[:min].nil?.should == false
      weather[:max].nil?.should == false
      weather[:weather_image].nil?.should == false
      weather[:location].should_not == ""
      weather[:weather_description].should_not == ""
      weather[:min].should_not == ""
      weather[:max].should_not == ""
      weather[:weather_image].should_not == ""
      weather[:precipIntensity].should_not == ""
      weather[:precipType].should_not == ""
    end
  
  
    it "should soft fail if all parsing fails" do

      stub_request(:get, @weather_url).
        with(:headers => {'Accept'=>'*/*; q=0.5, application/xml', 'Accept-Encoding'=>'gzip, deflate', 'User-Agent'=>'Ruby'}).
                 to_return(:status => 200, :body => "", :headers => {})
      
      lambda {
        
        Weather.fetch_data(@location, @address, @scale)
      }.should raise_error(NetworkError)
    end
  
    it "should soft fail if the network call fails" do 
      stub_request(:get, @weather_url).
          with(:headers => {'Accept'=>'*/*; q=0.5, application/xml', 'Accept-Encoding'=>'gzip, deflate', 'User-Agent'=>'Ruby'}).
                   to_return(:status => 200, :body => "", :headers => {})
   
          lambda {
            headlines = Weather.fetch_data(@location, @address, @scale)
          }.should raise_error(NetworkError)
    end  
  
    it "should soft fail if the call fails with a timeout error" do
      stub_request(:any, @weather_url).to_timeout 
      lambda {
        headlines = Weather.fetch_data(@location, @address, @scale)
        }.should raise_error()
     end
  end
  
end
