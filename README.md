# Little Printer Weather

A Little Printer publication which outputs a daily weather forecast. 

This is a Ruby and sinatra app. It provides a custom form for the subscriber to enter their location, which is returned to Remote. There is then further configuration for the subscriber to choose between Celsius and Farenheit.

Weather forecasts are fetched from http://free.worldweatheronline.com/ depending on the subscriber's location. 

See a sample publication: http://remote.bergcloud.com/publications/6


## Setup

The publication requires an API key from http://free.worldweatheronline.com/. This can be set in either an environment variable or in a `config.yml` file.

Environment variable:

    WEATHER_KEY=yourkeyhere

`config.yml`:

    weather_api_key: yourkeyhere


----

BERG Cloud Developer documentation: http://remote.bergcloud.com/developers/
