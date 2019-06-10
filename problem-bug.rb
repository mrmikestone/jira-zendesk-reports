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

# This class is used to interact with Zendesk, Jira, and the queryable
# integration between them to generate reports on mismatches between the
# two systems
class Reports
  def initialize
    @final_product = []
  end

  def fetch_zd_tickets
    @zendesk = ZendeskAPI::Client.new do |config|
      config.url = ENV['ZD_API_URL']

      config.username = ENV['ZD_USER']

      config.token = ENV['ZD_API_KEY']

      config.retry = true
    end
    puts 'Fetching ZD tickets...'
    @zd_tickets = []
    page = 1
    pages = (@zendesk.search(query: 'type:ticket ticket_type:problem status<solved').count / 100.0).ceil
    while pages >= page
      @zendesk.search(query: 'type:ticket ticket_type:problem status<solved', page: page).each do |i|
        @zd_tickets << { 'id' => i.id, 'priority' => i.priority, 'assignee' => i.group.name }
      end
      page += 1
    end
    puts 'ZD tickets fetched successfully.'
    @zd_tickets
  end

  def bulk_fetch_jira_information(hash_of_zendesk_and_jira_ids)
    jira_keys = []
    options = {
      username: ENV['JIRA_USER'],
      password: ENV['JIRA_PASS'],
      site: ENV['JIRA_URL'],
      context_path: '',
      auth_type: :basic
    }
    client = JIRA::Client.new(options)
    hash_of_zendesk_and_jira_ids.each do |w|
      jira_keys << w[3] if w[3] != 'orphan'
    end
    jira_keys.each_slice(50) do |jira_keys_array|
      non_array = jira_keys_array.join(',')
      binding.pry
      begin
          relevant_jira_information = client.Issue.jql("key IN (#{non_array})")
      rescue JIRA::HTTPError => e
        if e.response.code = '400'
          fetch_jira_priority_and_status(jira_keys_array)
        else
          raise e
        end
      end
    end
  end

  def fetch_jira_priority_and_status(hash_of_zendesk_and_jira_ids)
    puts 'Fetching priority and status of JIRA issues...'
    timestamp = DateTime.now.strftime('%Y-%m-%d')
    options = {
      username: ENV['JIRA_USER'],
      password: ENV['JIRA_PASS'],
      site: ENV['JIRA_URL'],
      context_path: '',
      auth_type: :basic
    }
    client = JIRA::Client.new(options)
    hash_of_zendesk_and_jira_ids.each do |w|
      if w.grep(/orphan/) == ['orphan']
        @final_product << { 'zd_link' => "#{ENV['ZD_LINK_URL']}/agent/tickets/#{w[0]}",
                            'zd_id' => w[0],
                            'zd_priority' => w[1],
                            'zd_assignee' => w[2],
                            'jira_id' => 'None',
                            'timestamp' => timestamp }
      else
        key = w.grep(/[A-Z]+-[0-9]+/)
        # binding.pry if key.size > 1
        next unless key != []

        begin
          relevant_jira_information = client.Issue.jql("key = #{key.first}")
          jira_array = [key.first, relevant_jira_information.first.fields['priority']['name'], relevant_jira_information.first.fields['status']['name']]
        rescue JIRA::HTTPError => e
          if e.response.code == '400'
            jira_array = [key.first, 'Unknown', 'Unknown']
          else
            raise e
          end
        end
        @final_product << { 'zd_link' => "#{ENV['ZD_LINK_URL']}/agent/tickets/#{w[0]}",
                            'zd_id' => w[0],
                            'zd_priority' => w[1],
                            'zd_assignee' => w[2],
                            'jira_id' => jira_array[0],
                            # zendesk priority is always all lower case, setting JIRA priority to lowercase makes matching easier
                            'jira_priority' => jira_array[1].downcase,
                            'jira_status' => jira_array[2],
                            'timestamp' => timestamp }
      end
    end
    puts 'Successfully pulled Priority and Status'
  end

  def match_zd_jira(ticket_id, ticket_priority, ticket_assignee)
    url = URI("https://jiraplugin.zendesk.com/integrations/jira/account/#{ENV['ZD_SUBDOMAIN']}/links/for_ticket?ticket_id=#{ticket_id}")

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Get.new(url)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{ENV['INTEGRATION_TOKEN']}"
    request['cache-control'] = 'no-cache'

    response = http.request(request)
    body = response.read_body
    formatted_body = JSON[body]
    if !formatted_body['links'][0].nil?
      array = formatted_body['links']
      array.each do |i|
        @zd_jira_match_array << [ticket_id, ticket_priority, ticket_assignee, i['issue_key']]
      end
    else
      @zd_jira_match_array << [ticket_id, ticket_priority, ticket_assignee, 'orphan']
    end
    @zd_jira_match_array
  end

  def grab_jira_id(zendesk_hash_array)
    zendesk_hash_array.each do |array|
      zd_id = array['id']
      zd_priority = array['priority']
      zd_assignee = array['assignee']
      @include_jira_keys = match_zd_jira(zd_id, zd_priority, zd_assignee)
    end
    puts 'JIRA tickets matched successfully'
    @include_jira_keys
  end

  def build_report
    @zd_jira_match_array = []

    zendesk_hash = fetch_zd_tickets

    puts 'Matching JIRA tickets to Zendesk IDs...'

    hash_of_zendesk_and_jira_ids = grab_jira_id(zendesk_hash)

    fetch_jira_priority_and_status(hash_of_zendesk_and_jira_ids)

    puts 'Function finished, sending results'

    @final_product.to_json
  end
end
