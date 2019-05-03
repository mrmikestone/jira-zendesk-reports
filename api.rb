require 'dotenv/load'
require 'rubygems'
require 'sinatra'
require 'rack'
require './problem-bug.rb'
require 'uri'
require 'net/http'
require 'openssl'

class ReportFetcher < Sinatra::Base
  get '/kitchen_sink' do
    content_type :json
    fetch = Reports.new
    report = fetch.build_report
    report
  end

  get '/zapier' do
    content_type :json
    fetch = Reports.new
    report = fetch.build_report
    puts report

    url = URI(ENV['ZAPIER_WEBHOOK'])

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Post.new(url)
    request['Content-Type'] = 'application/json'
    request['cache-control'] = 'no-cache'
    request.body = report
    # binding.pry
    response = http.request(request)
    puts response.read_body
  end
end
