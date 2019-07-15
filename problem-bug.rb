require 'dotenv/load'
require 'uri'
require 'net/http'
require 'csv'
require 'json'
require 'openssl'
require 'zendesk_api'
require 'jira-ruby'
require 'pry'
require 'rubygems'
require 'rack'
require 'pry-nav'

# This class is used to interact with Zendesk, Jira, and the queryable
# integration between them to generate reports on mismatches between the
# two systems
class Reports
  def initialize
    @jira_results = []
    @final_product = []
    @zd_tickets = []

    options = {
      username: ENV['JIRA_USER'],
      password: ENV['JIRA_PASS'],
      site: ENV['JIRA_URL'],
      context_path: '',
      auth_type: :basic
    }
    @jira_client = JIRA::Client.new(options)

    @zendesk = ZendeskAPI::Client.new do |config|
      config.url = ENV['ZD_API_URL']
      config.username = ENV['ZD_USER']
      config.token = ENV['ZD_API_KEY']
      config.retry = true
    end
  end

  def fetch_legend
    @legend = []
    url = URI("https://#{ENV['ZD_SUBDOMAIN']}.zendesk.com/api/services/jira/links")

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Get.new(url)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Basic #{ENV['INTEGRATION_TOKEN']}"
    request['cache-control'] = 'no-cache'

    response = http.request(request)

    formatted_body = JSON[response.read_body]
    legend = formatted_body['links']
    @jira_keys = []
    @legend += legend
    @since_id = legend.last['id']

    paginate_through_legend(@since_id) while (@legend.size % 1000).zero?
  end

  def paginate_through_legend(since_id)
    url = URI("https://#{ENV['ZD_SUBDOMAIN']}.zendesk.com/api/services/jira/links?since_id=#{since_id}")

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Get.new(url)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Basic #{ENV['INTEGRATION_TOKEN']}"
    request['cache-control'] = 'no-cache'

    response = http.request(request)

    formatted_body = JSON[response.read_body]
    legend = formatted_body['links']
    @legend += legend

    @since_id = legend.last['id']
  end

  def fetch_zd_tickets
    puts 'Fetching ZD tickets...'
    time = Time.now
    page = 1
    pages = (@zendesk.search(query: 'type:ticket ticket_type:problem status<solved').count / 100.0).ceil
    while pages >= page
      @zendesk.search(query: 'type:ticket ticket_type:problem status<solved', page: page).each do |i|
        @zd_tickets << { 'zd_id' => i.id, 'zd_priority' => i.priority, 'zd_assignee' => i.group.name, 'timestamp' => time }
      end
      page += 1
    end
    puts 'ZD tickets fetched successfully.'
  end

  def bulk_fetch_jira_information
    @jira_keys.each_slice(50) do |jira_keys_array|
      string_of_jira_keys = jira_keys_array.join(',')
      begin
        relevant_jira_information = @jira_client.Issue.jql("id IN (#{string_of_jira_keys})")
      rescue JIRA::HTTPError => e
        if e.response.code == '400'
          reconcile_bulk_jira_fetch(jira_keys_array)
        else
          raise e
        end
      end

      parse_jira_body(relevant_jira_information)
    end
  end

  def reconcile_bulk_jira_fetch(jira_keys_array)
    jira_keys_array.each do |key|
      begin
        relevant_jira_information = @jira_client.Issue.jql("id = #{key}")
      rescue JIRA::HTTPError => e
        if e.response.code == '400'
          @jira_results << { 'key' => key,
                             'priority' => 'unknown',
                             'status' => 'unknown' }
        else
          raise e
        end
      end

      parse_jira_body(relevant_jira_information) unless relevant_jira_information.nil?
    end
  end

  def parse_jira_body(jira_body)
    jira_body.each do |i|
      results = if i.fields['priority'].nil?
                  { 'priority' => 'Unknown',
                    'status' => i.fields['status']['name'],
                    'key' => i.key,
                    'id' => i.id
                  }
                else
                  {
                    'priority' => i.fields['priority']['name'],
                    'status' => i.fields['status']['name'],
                    'key' => i.key,
                    'id' => i.id
                  }
                end
      @jira_results << results
    end
  end

  def consolidate_zendesk
    @zd_tickets.each do |zd|
      @legend.each do |mini_legend|
        next unless mini_legend.value?(zd['zd_id'].to_s)

        zd.store('jira_key', mini_legend['issue_key'])
        zd.store('jira_id', mini_legend['issue_id'])
        @jira_keys << mini_legend['issue_id']
      end
    end
  end

  def build_final_product
    @count = 1
    @failcase = 1
    @zd_tickets.each do |match|
      if match.key?('jira_id')
        @count += 1
        @jira_results.each do |jira|
          next unless jira.value?(match['jira_id'])

          match.store('jira_priority', jira['priority'].downcase)
          match.store('jira_status', jira['status'])
          @final_product << match
        end
      else
        @failcase += 1
        @final_product << match
      end
    end
  end

  def build_report
    fetch_legend

    fetch_zd_tickets

    puts 'Matching JIRA tickets to Zendesk IDs...'

    consolidate_zendesk

    bulk_fetch_jira_information

    build_final_product

    puts 'Function finished, sending results'

    binding.pry

    @final_product.to_json
  end
end
