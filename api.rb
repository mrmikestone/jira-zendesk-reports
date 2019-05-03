require 'dotenv/load'
require 'rubygems'
require 'sinatra'
require 'rack'
require './problem-bug.rb'

class ReportFetcher < Sinatra::Base
  get '/kitchen_sink' do
    content_type :json
    fetch = Reports.new
    report = fetch.build_report
    report
  end
end
