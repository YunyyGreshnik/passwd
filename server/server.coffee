Meteor.startup () ->
  # code to run on server at startup
  # console.log "server startup"
  null

Meteor.publish 'passwds', () ->
  Passwds.find {'user': @userId}, {}

Meteor.publish 'pphashes', ()->
  Passwds.find {'user': @userId}, {}

Meteor.methods {
  'insertPasswd': (userId, title, username, password) =>
    Passwds.insert {
      'user': userId
      'title': title
      'username': username
      'password': password
    }
}

Meteor.methods {
  'insertPpHash': (userId, pphash) =>
    console.log userId
    PpHashes.update {
      'user': @userId
    },
    {
      '$set': { 'pphash': pphash }
    },
    {
      'upsert': true
    }
}
