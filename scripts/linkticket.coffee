# Commands:
#   `<project>-<ticketid>` - Return link to that Jira ticket in a given project

moment = require("moment")
btoa = require("btoa")
{TextMessage} = require("hubot/src/message")

jira_user = process.env.HUBOT_JIRA_USER
jira_password = process.env.HUBOT_JIRA_PASSWORD

BOT_NAMES = ["jirabot"]
ALLOWED_PROJECTS = /\b(LK)-\d+/gi
BASE_URL = "https://jira.slac.stanford.edu/"

BROWSE_URL = "#{BASE_URL}browse/"
API_BASE_URL = "#{BASE_URL}rest/api/latest/issue/"

module.exports = (robot) ->
  rootCas = require('ssl-root-cas/latest').create()
  require('https').globalAgent.options.ca = rootCas
  ticketId = null
  robot.listen(
    # Matcher
    (message) ->
      if message instanceof TextMessage
        match = message.match(ALLOWED_PROJECTS)
        if match and message.user.name not in BOT_NAMES
          match
        else
          false
      else
        false
    # Callback
    (response) ->
      # Link to the associated tickets
      issueResponses(robot, response)
  )

makeHeaders = ->
  auth = btoa("#{jira_user}:#{jira_password}")

  return {
    Accept: "application/json"
    Authorization: "Basic #{auth}"
  }


issueResponses = (robot, msg) ->
  ticketIds = Array.from(new Set(msg.match))
  for ticketId in ticketIds
    ticketId = ticketId.toUpperCase()
    last = robot.brain.get(ticketId)
    now = moment()
    robot.brain.set(ticketId, now)
    if last and now.isBefore last.add(1, 'minute')
      return
    urlstr="#{API_BASE_URL}#{ticketId}"
    headers = makeHeaders()
    robot.http(urlstr,{ecdhCurve: 'auto'}).headers(headers).get() (err, res, body) ->
      if (not res)
        msg.send("Null response from GET #{urlstr}")
        msg.send("Error: #{err}")
        return
      if res.statusCode in [401, 403]
        msg.send("Protected: <#{BROWSE_URL}#{ticketId}|#{ticketId}>")
        return
      if res.statusCode == 404
        # Do Nothing
        # If Something is wrong with Jira, this might
        return
      if err
        msg.send("(Error Retrieving ticket Jira: `#{err}`)")
        return
      try
        issue = JSON.parse(body)
        attachment = getAttachment(issue)
        msg.send({attachments: [attachment]})
      catch error
        msg.send("Error parsing JSON for #{ticketId}: `#{error}`")

getAttachment = (issue) ->
  response = fallback: ''
  response.fallback = issue.key + ": " + issue.fields.summary
  response.color = "#88bbdd"
  response.mrkdwn_in = [ 'text' ]
  # Parse text as markdown
  issue_md = "<#{BROWSE_URL}#{issue.key}|#{issue.key}>"
  status_md = "`#{issue.fields.status.name}`"
  response.text = issue_md + ": " + status_md + " " + issue.fields.summary
  response.footer = 'Unassigned'
  if issue.fields.assignee
    response.footer = issue.fields.assignee.displayName
  if "priority" in issue.fields
    response.footer_icon = issue.fields.priority.iconUrl
  response.ts = moment(issue.fields.created).format("X")
  return response
