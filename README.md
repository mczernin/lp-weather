# Little Printer Weather

A Little Printer publication which outputs a daily weather forecast. 

This is a Ruby and Sinatra app. It provides a custom form for the subscriber to enter their location, which is returned to Remote. There is then further configuration for the subscriber to choose between Celsius and Farenheit.

Weather forecasts are fetched from http://forecast.io/ depending on the subscriber's location. 

See a sample publication: http://remote.bergcloud.com/publications/6


## Setup

The publication requires an API key from https://developer.forecast.io/ . This can be set in either an environment variable or in a `config.yml` file.

Environment variable:

    WEATHER_KEY=yourkeyhere

`config.yml`:

    weather_api_key: yourkeyhere


## Tests

Run tests like:

	$ bundle exec rspec publication_spec.rb 

----

BERG Cloud Developer documentation: http://remote.bergcloud.com/developers/
