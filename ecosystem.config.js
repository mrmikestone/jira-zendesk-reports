module.exports = {
  apps : [{
    name: 'jirazendesk',
    script: 'bundle',
    args: 'exec rackup -p 80',
    merge_logs:  true,
    error_file: '/var/log/node/app_error.log',
    out_file: '/var/log/node/app_error.log'
  }]
}
