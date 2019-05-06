# jira-zendesk-reports
A Sinatra app for comparing linked tickets between Zendesk and Jira

If you're like me and you find the integration between Zendesk and JIRA to be excellent at creating tickets and about nothing else, have I got great news for you.

This app is designed to aggregate and report the status and priority of linked Zendesk and JIRA tickets.

### Getting Started

Clone the repository using your preferred method

    SSH: `git clone git@github.com:riskalyze/jira-zendesk-reports.git`

    HTTPS: `git clone https://github.com/riskalyze/test-service.git`

Copy the .env.dist to a .env file
    `cp .env.dist .env`

Fill in all the values in the .env file (Zapier URL is optional if you'd like to set up a zap to consume this report)

For the .env value INTEGRATION_TOKEN, you'll have to do some sleuthing in Zendesk(Maybe you can contact support to get it, I dunno, I haven't tried).
Open up a ticket in Zendesk that is linked to a JIRA issue. Open up Dev tools (F12) and open the Network tab.
Refresh the page and look for an item with a name like `for_ticket?ticket_id=1234567`, it will be close to the bottom, but you may have to scroll up a bit.
In the Headers tab of that request, at the very bottom is an Authorization Header `Bearer <token>`. COPY ONLY THE TOKEN, DO NOT INCLUDE `Bearer`.

Run `bundle install`

Run `bundle exec rackup -p 4567`

The app is now running on port 4567

### API Documentation
The jira-zendesk-reports app has 3 endpoints

1) `/status`

    Returns 200. If it doesn't, run.

2) `/kitchen_sink`

    Currently, this endpoint only responds to a `GET` request and will return an array of hashes. This takes several minutes and varies depending on the number of open Zendesk Problems.

    Example response:

     ```json
     [
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
     ]
     ```

3) `/zapier`
    Currently, this endpoint only responds to a `GET` request

    Provided you have set a webhook URL in the .env file, this request will POST the response from `/kitchen_sink` on to the zapier webhook
