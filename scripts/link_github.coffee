# Commands:
#   `<user>/<repo>/#<issue_or_pr>` - Return link to that github issue for tracked users/orgs

moment = require("moment")
btoa = require("btoa")
{TextMessage} = require("hubot/src/message")

gh_host = if process.env.HUBOT_GITHUB_SERVER then process.env.HUBOT_GITHUB_SERVER else "github.com"
gh_host = if gh_host.slice(-1) != "/" then gh_host + "/"

gh_api = "https://api.#{gh_host}"
gh_ui = "https://#{gh_host}"
gh_token = process.env.HUBOT_GITHUB_TOKEN
gh_ignore_users = process.env.HUBOT_GITHUB_IGNORE_USERS
gh_tracked_users = process.env.HUBOT_GITHUB_TRACKED_USERS

IGNORE_USERS = if gh_ignore_users then gh_ignore_users.split(",") else []
TRACKED_USERS = if gh_tracked_users then gh_tracked_users.split(",") else []

USERS_URL = "#{gh_api}users/"
REPOS_URL = "#{gh_api}repos/"

module.exports = (robot) ->
  rootCas = require('ssl-root-cas/latest').create()
  require('https').globalAgent.options.ca = rootCas
  issueId = null
  maybeUpdateRepos(robot, null)
  robot.listen(
    # Matcher
    (message) ->
      if message instanceof TextMessage
        repos = []
        for user in TRACKED_USERS
          user_url = "#{USERS_URL}#{user}/repos"
          console.log user_url
          console.log robot.brain.get(user_url)
          repos = repos.concat(robot.brain.get(user_url).repos)
        repoPattern = repos.join "|"
        issuePattern = ///\b(#{repoPattern})#\d+///gi
        match = message.match(issuePattern)
        if match and message.user.name not in IGNORE_USERS
          match
        else
          false
      else
        false
    # Callback
    (response) ->
      # Link to the associated tickets
      issueResponses(robot, response)
      maybeUpdateRepos(robot, response)
  )

makeHeaders = ->
  if gh_token
    return {Authorization: "token #{gh_token}"}
  return {}


issueResponses = (robot, msg) ->
  issueIds = Array.from(new Set(msg.match))
  for issueId in issueIds
    issueIdUpper = issueId.toUpperCase()
    last = robot.brain.get(issueIdUpper)
    now = moment()
    if last and now.isBefore moment(last).add(1, 'minute')
      return
    robot.brain.set(issueIdUpper, now)
    issuePattern = /(.*)\/(.*)#(.*)/
    matched = issueId.match(issuePattern)
    user = matched[1]
    repo = matched[2]
    issue = matched[3]
    urlstr="#{REPOS_URL}#{user}/#{repo}/issues/#{issue}"
    headers = makeHeaders()
    robot.http(urlstr,{ecdhCurve: 'auto'}).headers(headers).get() (err, res, body) ->
      if (not res)
        msg.send("Null response from GET #{urlstr}")
        msg.send("Error: #{err}")
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
        attachment = getAttachment(user, repo, issue)
        msg.send({attachments: [attachment]})
      catch error
        msg.send("Error parsing JSON for #{issueId}: `#{error}`")


getAttachment = (user, repo, issue) ->
  response = fallback: ''
  response.fallback = issue.number + ": " + issue.title
  response.color = "#88bbdd"
  response.mrkdwn_in = [ 'text' ]
  # Parse text as markdown
  issue_md = "<#{gh_ui}#{user}/#{repo}/issues/#{issue.number}|#{user}/#{repo}##{issue.number}>"
  status_md = "`#{issue.state}`"
  response.text = issue_md + ": " + status_md + " " + issue.title
  response.footer = 'Unassigned'
  if issue.assignee
    response.footer = issue.assignee.login
  # labels?
  # response.footer_icon = issue.fields.priority.iconUrl
  response.ts = moment(issue.created_at).format("X")
  return response


maybeUpdateRepos = (robot, msg) -> 
  for user in TRACKED_USERS
    user_url = "#{USERS_URL}#{user}/repos"
    timeAndRepos = robot.brain.get(user_url)
    now = moment()
    if timeAndRepos and now.isBefore moment(timeAndRepos.last).add(1, 'hour')
      return
    do (now, user_url) ->
      repos = []
      finished = () ->
        robot.brain.set(user_url, {last: now, repos:repos})
        console.log "Updated: #{user_url}"
        console.log repos
      updateRepos(robot, msg, user_url, repos, finished)


updateRepos = (robot, msg, next_url, repos, finished) ->
  headers = makeHeaders()
  robot.http(next_url, {ecdhCurve: 'auto'}).headers(headers).get() (err, res, body) ->
    if res.statusCode != 200
      console.log body
    if err
      console.log err
    if msg
      msg.send("(Error Retrieving Projects: `#{err}`)")
      return
    try
      repoList = JSON.parse(body)
      for repo in repoList
        repos.push repo.full_name
      links = parseLinkHeader res.headers.link if res.headers.link
      if links and links.next
        updateRepos(robot, msg, links.next, repos, finished)
      else
        finished()
    catch error
      console.log error
      if msg
        msg.send("Error parsing JSON for Projects: `#{error}`")


parseLinkHeader = (header) ->
  parts = header.split(',')
  links = {}
  for p in parts
    section = p.split(';')
    url = section[0].replace(/<(.*)>/, '$1').trim()
    name = section[1].replace(/rel="(.*)"/, '$1').trim()
    links[name] = url
  return links
