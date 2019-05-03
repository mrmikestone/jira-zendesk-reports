# jira-zendesk-reports
A Sinatra app for comparing linked tickets between Zendesk and Jira

If you're like me and you find the integration between Zendesk and JIRA to be excellent at creating tickets and about nothing else, have I got great news for you.
This app is designed to aggregate and report the status and priority of linked Zendesk and JIRA tickets.

### Getting Started

Clone the repository using your preferred method
    SSH: ```git clone git@github.com:riskalyze/jira-zendesk-reports.git```
    HTTPS: ```git clone https://github.com/riskalyze/test-service.git```

Copy the .env.dist to a .env file
    `cp .env.dist .env`

Fill in all the values in the .env file (Zapier URL is optional if you'd like to set up a zap to consume this report)

Run `bundle install`

Run `bundle exec rackup -p 4567`

The app is now running on port 4567

### API Documentation
The jira-zendesk-reports app has 3 endpoints

1) `/kitchen_sink`
    Currently, this endpoint only responds to a `GET` request and will return an array of hashes:
    Example response:
     ```[
        {
            "zd_link":"https://zendesk.com/agent/tickets/:id",
            "zd_id":280543,
            "zd_priority":"low",
            "jira_id":"None"
        },
        {
            "zd_link":"https://zendesk.com/agent/tickets/:id",
            "zd_id":280310,
            "zd_priority":"normal",
            "jira_id":"RSKBUGS-214",
            "jira_priority":"High",
            "jira_status":"In Progress"
        }
        ]```

2) `/zapier`
    Currently, this endpoint only responds to a `GET` request

    Provided you have set a webhook URL in the .env file, this request will POST the response from `/kitchen_sink` on to the zapier webhook
