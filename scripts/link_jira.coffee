# Commands:
#   `<project>-<ticketid>` - Return link to that Jira ticket in a given project

moment = require("moment")
btoa = require("btoa")
{TextMessage} = require("hubot/src/message")

jira_server = process.env.HUBOT_JIRA_SERVER
jira_user = process.env.HUBOT_JIRA_USER
jira_password = process.env.HUBOT_JIRA_PASSWORD
jira_ignore_users = process.env.HUBOT_JIRA_IGNORE_USERS

jira_server = if jira_server.slice(-1) != "/" then jira_server + "/"

IGNORE_USERS = if jira_ignore_users then jira_ignore_users.split(",") else []
BROWSE_URL = "#{jira_server}browse/"

API_URL = "#{jira_server}rest/api/latest/"
ISSUE_URL = "#{API_URL}issue/"
PROJECT_URL = "#{API_URL}project/"


module.exports = (robot) ->
  rootCas = require('ssl-root-cas/latest').create()
  require('https').globalAgent.options.ca = rootCas
  ticketId = null
  maybeUpdateProjects(robot, null)
  robot.listen(
    # Matcher
    (message) ->
      if message instanceof TextMessage
        projectsPattern = robot.brain.get(PROJECT_URL).projects.join "|"
        ticketPattern = ///\b(#{projectsPattern})-\d+///gi
        match = message.match(ticketPattern)
        if match and message.user.name not in IGNORE_USERS
          console.log match
          match
        else
          false
      else
        false
    # Callback
    (response) ->
      # Link to the associated tickets
      issueResponses(robot, response)
      maybeUpdateProjects(robot, response)
  )

makeHeaders = ->
  headers = {
    Accept: "application/json"
  }
  
  if jira_user
    headers['Authorization'] = "Basic " + btoa("#{jira_user}:#{jira_password}")
  return headers


issueResponses = (robot, msg) ->
  ticketIds = Array.from(new Set(msg.match))
  for ticketId in ticketIds
    ticketId = ticketId.toUpperCase()
    last = robot.brain.get(ticketId)
    now = moment()
    robot.brain.set(ticketId, now)
    if last and now.isBefore last.add(1, 'minute')
      return
    urlstr="#{ISSUE_URL}#{ticketId}"
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


maybeUpdateProjects = (robot, msg) -> 
  timeAndProjects = robot.brain.get(PROJECT_URL)
  now = moment()
  if timeAndProjects and now.isBefore timeAndProjects.last.add(1, 'hour')
    return
  headers = makeHeaders()
  robot.http(PROJECT_URL, {ecdhCurve: 'auto'}).headers(headers).get() (err, res, body) ->
    if err
      console.log err
      if msg
        msg.send("(Error Retrieving Projects: `#{err}`)")
      return
    try
      projects = []
      projectList = JSON.parse(body)
      for project in projectList
        projects.push project.key
      robot.brain.set(PROJECT_URL, {last: now, projects: projects})
    catch error
      console.log error
      if msg
        msg.send("Error parsing JSON for Projects: `#{error}`")
