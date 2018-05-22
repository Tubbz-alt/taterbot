# Commands:
#   `<github_user>@github` - Return a mention the the Slack user of a given Github username

{TextMessage} = require("hubot/src/message")
{WebClient} = require '@slack/client'

slack_app_token = process.env.HUBOT_SLACK_APP_TOKEN
gh2slack_profile_label = process.env.HUBOT_GH2SLACK_LABEL
#gh2slack_ignore_users = process.env.HUBOT_GH2SLACK_IGNORE_USERS

web = new WebClient(slack_app_token)

IGNORE_USERS = [] # if gh_ignore_users then gh_ignore_users.split(",") else []

ghPattern = /\b(.*)@github/gi
GITHUB_ID = "github_id"
LABEL_ID = gh2slack_profile_label

module.exports = (robot) ->
  github_id = null
  rootCas = require('ssl-root-cas/latest').create()
  require('https').globalAgent.options.ca = rootCas
  loadUsers(robot)
  robot.listen(
    # Matcher
    (message) ->
      if message instanceof TextMessage
        match = message.match(ghPattern)
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
  )


issueResponses = (robot, msg) ->
  githubIds = Array.from(new Set(msg.match))
  for githubId in githubIds
    userPattern = /(.*)@github/
    matched = githubId.match(userPattern)
    gh_id = matched[1]
    if gh_id of robot.brain.gh2slack
      slackId = robot.brain.gh2slack[gh_id]
      attachment = getAttachment(gh_id, slackId)
      msg.send({attachments: [attachment]})


getAttachment = (gh_id, slackId) ->
  response = fallback: ''
  response.fallback = "#{gh_id} -> #{slackId}"
  response.mrkdwn_in = [ 'text' ]
  response.text = "#{gh_id} -> <@#{slackId}>"
  return response


loadUsers = (robot) -> 
  users = robot.brain.users()
  robot.brain.gh2slack = {}
  for id, user of users
    do (id, user) ->
      web.users.profile.get({user:id}).then (result) ->
        profile = result.profile
        fields = profile.fields if profile.fields
        github_field = profile.fields[LABEL_ID] if fields and profile.fields[LABEL_ID]
        github_id = github_field.value if github_field
        if github_id
          user[GITHUB_ID] = github_id
          robot.brain.gh2slack[github_id] = user.id
          console.log "Registered mapping #{github_id} -> #{user.id}"
