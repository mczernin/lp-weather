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
      :min => '10',
      :max => '15',
      :units => 'C'
    }
  end
  
  describe 'edition' do
   it 'should return html for a get with location, address and scale' do
     Weather.should_receive(:fetch_data).with(@location, @address, @scale).and_return(@forecast)
     get "/edition/?location=#{URI.escape(@location)}&address=#{URI.escape(@address)}&scale=#{@scale}"
     last_response.should be_ok
     
     # should include location/forecast/etc
     last_response.body.scan(@forecast[:address]).length.should == 1
     last_response.body.scan("#{@forecast[:weather_image]}.png").length.should == 1
     last_response.body.scan(@forecast[:min]).length.should == 1
     last_response.body.scan(@forecast[:max]).length.should == 1
     
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
  
  describe 'post to validation' do
    
    # Validation is done by an external website. Obvs we don't want to test that that works, only that we handle whatever it returns correctly
    
    # Valid address works
    it 'should return response valid = true for an address that is valid' do
      location = '51.5215,0.1389'
      
      Weather.should_receive(:location_is_valid).exactly(1).times.and_return(true)
      post '/validate_config/', :config => {:location => location}.to_json
      resp = JSON.parse(last_response.body)
      resp['valid'].should == true
    end
    
    # Invalid address does not work
    it 'should return response valid = false for an address that is not valid. This should also include an error message from the third party' do
      location = '51.5215,0.1389'
      
      Weather.should_receive(:location_is_valid).exactly(1).times.and_return(false)
      post '/validate_config/', :config => {:location => location}.to_json
      resp = JSON.parse(last_response.body)
      resp['valid'].should == false
      resp['errors'].should == ["Unable to find the location of #{location}"]
    end
    
    # Failiure to validate with an error is retried twice before returning a 502
    it 'should retry if the call fails at a network level then return a 502' do
      location = '51.5215,0.1389'
      
      Weather.should_receive(:location_is_valid).exactly(3).times.and_raise(NetworkError)

      post '/validate_config/', :config => {:location => location}.to_json
      last_response.status.should == 502
      
    end

  end
  
  
  describe 'get a sample' do
  
    it 'should return some html for get requests to /sample.html' do
      get '/sample/'
      last_response.body.scan(Weather::SAMPLE_DATA[:location]).length.should == 1
      last_response.body.scan(Weather::SAMPLE_DATA[:weather_description]).length.should == 1
    end
    
  end
  
  describe 'get meta.json' do

    it 'should return json for meta.json' do
      get '/meta.json'
      last_response["Content-Type"].should == "application/json;charset=utf-8"
      json = JSON.parse(last_response.body)
      json["name"].should_not == nil
      json["description"].should_not == nil
      json["delivered_every"].should_not == nil
    end
  
  end


  describe 'get icon' do
  
    it 'should return a png for /icon' do
      get '/icon.png'
      last_response['Content-Type'].should == 'image/png'
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
      @location = "W1T 4JZ"
      @address = 'The BT Tower'

      @scale = 'celsius'
      
      @weather_url = "http://free.worldweatheronline.com/feed/weather.ashx?format=json&key=#{settings.weather_api_key}&num_of_days=1&query=#{URI.escape(@location)}"
      @forecast = { 
        :location => @location,
        :address => @address,
        :weather_image => 'sunny',
        :weather_description => 'Sunny',
        :min => '10',
        :max => '15',
        :units => 'C'
      }
    end
   
    it "should return a weather forecast" do 
    
      file = File.open(File.join( "spec_assets","stub_data.json"), "rb")
      return_content = file.read
      
      stub_request(:get, @weather_url).
        with(:headers => {'Accept'=>'*/*; q=0.5, application/xml', 'Accept-Encoding'=>'gzip, deflate', 'User-Agent'=>'Ruby'}).
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
  
  describe 'location_valid?' do
    before(:each) do
      @location='York'
      @search_url = "http://www.worldweatheronline.com/feed/search.ashx?format=json&key=#{settings.weather_api_key}&num_of_results=1&query=#{URI.escape(@location)}"
      
    end
    
    
    it '# should return true for a valid location' do
      stub_request(:get, @search_url).
        with(:headers => {'Accept'=>'*/*; q=0.5, application/xml', 'Accept-Encoding'=>'gzip, deflate', 'User-Agent'=>'Ruby'}).
        to_return(:status => 200, :body => File.open('spec_assets/location_success.json'), :headers => {})
      
      Weather.location_is_valid(@location).should == true
    end
    
    it '#should return false for an invalid location' do
      stub_request(:get, @search_url).
      with(:headers => {'Accept'=>'*/*; q=0.5, application/xml', 'Accept-Encoding'=>'gzip, deflate', 'User-Agent'=>'Ruby'}).
      to_return(:status => 200, :body => File.open('spec_assets/location_fail.json'), :headers => {})
      Weather.location_is_valid(@location).should == false
    end

    
    it '#should raise a Network error for a timeout' do
      stub_request(:any, @search_url).to_timeout 
      
      lambda {
        Weather.location_is_valid @location
        }.should raise_error()
    end
    
    it '#should raise a Parse error for a problem parsing' do
        stub_request(:get, @search_url).
        with(:headers => {'Accept'=>'*/*; q=0.5, application/xml', 'Accept-Encoding'=>'gzip, deflate', 'User-Agent'=>'Ruby'}).
        to_return(:status => 200, :body => File.open('spec_assets/location_parse_fail.xml'), :headers => {})

      lambda {
        Weather.location_is_valid @location
        }.should raise_error(PermanentError)
    end
    
  end
end