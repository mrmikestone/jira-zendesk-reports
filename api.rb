require 'dotenv/load'
require 'rubygems'
require 'sinatra'
require 'rack'
require './problem-bug.rb'
require 'uri'
require 'net/http'
require 'openssl'

class ReportFetcher < Sinatra::Base
  get '/status' do
    200
  end

  get '/kitchen_sink' do
    content_type :json
    Reports.new.build_report
  end

  get '/zapier' do
    content_type :json
    report = Reports.new.build_report
    puts report

    url = URI(ENV['ZAPIER_WEBHOOK'])

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Post.new(url)
    request['Content-Type'] = 'application/json'
    request['cache-control'] = 'no-cache'
    request.body = report
    response = http.request(request)
    puts response.read_body
  end
end
