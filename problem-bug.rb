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
    # legend.each do |legend_hash|
    #   @jira_keys << legend_hash['issue_key']
    # end
    @since_id = legend.last['id']
    # binding.pry
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
    # binding.pry
    @since_id = legend.last['id']
  end

  def fetch_zd_tickets
    puts 'Fetching ZD tickets...'
    page = 1
    pages = (@zendesk.search(query: 'type:ticket ticket_type:problem status<solved').count / 100.0).ceil
    while pages >= page
      @zendesk.search(query: 'type:ticket ticket_type:problem status<solved', page: page).each do |i|
        @zd_tickets << { 'id' => i.id, 'priority' => i.priority, 'assignee' => i.group.name }
      end
      page += 1
    end
    puts 'ZD tickets fetched successfully.'
  end

  def bulk_fetch_jira_information
    # jira_keys = []
    # @zd_jira_match_array.each do |w|
    #   # binding.pry
    #   jira_keys << w[3] if w[3] != 'orphan'
    # end
    @jira_keys.each_slice(50) do |jira_keys_array|
      string_of_jira_keys = jira_keys_array.join(',')
      begin
        relevant_jira_information = @jira_client.Issue.jql("key IN (#{string_of_jira_keys})")
      rescue JIRA::HTTPError => e
        if e.response.code == '400'
          reconcile_bulk_jira_fetch(jira_keys_array)
        else
          raise e
        end
      end
      # binding.pry
      parse_jira_body(relevant_jira_information)
    end
  end

  def reconcile_bulk_jira_fetch(jira_keys_array)
    jira_keys_array.each do |key|
      begin
        relevant_jira_information = @jira_client.Issue.jql("key = #{key}")
      rescue JIRA::HTTPError => e
        if e.response.code == '400'
          @jira_results << { 'key' => key,
                             'priority' => 'unknown',
                             'status' => 'unknown' }
        else
          raise e
        end
      end
      # binding.pry
      parse_jira_body(relevant_jira_information)
    end
  end

  def parse_jira_body(jira_body)
    jira_body.each do |i|
      results = if i.fields['priority'].nil?
                  { 'priority' => 'Unknown',
                    'status' => i.fields['status']['name'],
                    'key' => i.key }
                else
                  {
                    'priority' => i.fields['priority']['name'],
                    'status' => i.fields['status']['name'],
                    'key' => i.key
                  }
              end
      @jira_results << results
    end
    # binding.pry
  end

  def consolidate_zendesk
    @zd_tickets.each.with_index do |zd, index|
      @legend.each do |mini_legend|
        # binding.pry
        next unless mini_legend.value?(zd['id'].to_s)

        @zd_tickets[index].store('jira_key', mini_legend['issue_key'])
        @jira_keys << mini_legend['issue_key']
      end
    end
    # binding.pry
  end

  def build_final_product
    @zd_tickets.each do |match|
      if match.key?('jira_key')
        @jira_results.each do |jira|
          next unless jira.value?(match['jira_key'])

          match.store('jira_priority', jira['priority'])
          match.store('jira_status', jira['status'])
          @final_product << match
        end
      else
        @final_product << match
      end
    end
    binding.pry
  end

  # def match_zd_jira(ticket_id, ticket_priority, ticket_assignee)
  #   url = URI("https://jiraplugin.zendesk.com/integrations/jira/account/#{ENV['ZD_SUBDOMAIN']}/links/for_ticket?ticket_id=#{ticket_id}")

  #   http = Net::HTTP.new(url.host, url.port)
  #   http.use_ssl = true
  #   http.verify_mode = OpenSSL::SSL::VERIFY_NONE

  #   request = Net::HTTP::Get.new(url)
  #   request['Content-Type'] = 'application/json'
  #   request['Authorization'] = "Bearer #{ENV['INTEGRATION_TOKEN']}"
  #   request['cache-control'] = 'no-cache'

  #   response = http.request(request)
  #   body = response.read_body
  #   formatted_body = JSON[body]
  #   if !formatted_body['links'][0].nil?
  #     array = formatted_body['links']
  #     array.each do |i|
  #       @zd_jira_match_array << [ticket_id, ticket_priority, ticket_assignee, i['issue_key']]
  #     end
  #   else
  #     timestamp = DateTime.now.strftime('%Y-%m-%d')
  #     @final_product << { 'zd_id' => ticket_id,
  #                         'zd_link' => "#{ENV['ZD_LINK_URL']}/agent/tickets/#{ticket_id}",
  #                         'zd_priority' => ticket_priority,
  #                         'zd_assignee' => ticket_assignee,
  #                         'jira_id' => 'None',
  #                         'timestamp' => timestamp }
  #   end
  # end

  # def grab_jira_id
  #   @zd_tickets.each do |array|
  #     match_zd_jira(array['id'], array['priority'], array['assignee'])
  #   end
  #   puts 'JIRA tickets matched successfully'
  # end

  # def consolidate_jira_zendesk
  #   @jira_results.each do |jira_block|
  #     @zd_jira_match_array.each_with_index do |zd_array, _i|
  #       match = zd_array.find { |x| x == jira_block['key'] }
  #       next if match.nil?

  #       timestamp = DateTime.now.strftime('%Y-%m-%d')
  #       @final_product << { 'zd_link' => "#{ENV['ZD_LINK_URL']}/agent/tickets/#{zd_array[0]}",
  #                           'zd_id' => zd_array[0],
  #                           'zd_priority' => zd_array[1],
  #                           'zd_assignee' => zd_array[2],
  #                           'jira_id' => zd_array[3],
  #                           # zendesk priority is always all lower case, setting JIRA priority to lowercase makes matching easier
  #                           'jira_priority' => jira_block['priority'].downcase,
  #                           'jira_status' => jira_block['status'],
  #                           'timestamp' => timestamp }
  #     end
  #   end
  # end

  def build_report
    @zd_jira_match_array = []

    fetch_legend

    fetch_zd_tickets

    puts 'Matching JIRA tickets to Zendesk IDs...'

    # grab_jira_id

    consolidate_zendesk

    bulk_fetch_jira_information

    build_final_product

    puts 'Function finished, sending results'

    @final_product.to_json
    binding.pry
  end
end
