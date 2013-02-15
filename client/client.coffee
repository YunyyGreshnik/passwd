Meteor.subscribe "passwds"
Meteor.subscribe "pphashes"

activateInput = (input) ->
  input.focus()
  input.select()

# Returns an event map that handles the "escape" and "return" keys and
# "blur" events on a text input (given by selector) and interprets them as
# "ok" or "cancel"
okCancelEvents = (selector, callbacks) ->
  ok = callbacks.ok or () -> null
  cancel = callbacks.cancel or () -> null

  events = {}
  events["keyup #{selector}, keydown #{selector}, focusout #{selector}"] =
    (ev) ->
      if ev.type == 'keydown' and ev.which == 27
        cancel.call this, ev
      else if ev.type == 'keyup' and ev.which == 13 or
              ev.type == 'focusout'
        value = ev.target.value
        if value
          ok.call this, value, ev
        else
          cancel.call this, ev
      null
  events


Template.usercontent.events {
  'keyup #search': (ev) ->
    Session.set 'search', ev.srcElement.value
    null

}

deleteCurrentUndo = () ->
  Session.set 'passwd-undo'

generatePasswdUndo = (obj, isUpdate) ->
  isUpdate = isUpdate or false
  insertObj = {}
  for own key, value of obj
    if not isUpdate or ( key != '_id' and key != 'user')
      insertObj[key] = value
  undoObj = {
    _id: obj._id
    insert: insertObj
    isUpdate: isUpdate
  }
  Session.set 'passwd-undo', undoObj
  null

Template.undo.events {
  'click #button-undo': () ->
    undoObj = Session.get 'passwd-undo'
    if undoObj.isUpdate
      Passwds.update {'_id' : undoObj._id}, {'$set': undoObj.insert}
    else
      Meteor.call 'insertPasswdObj',
                  undoObj.insert
    deleteCurrentUndo()
}

Template.undo.helpers {
  undoSet: () ->
    Session.get('passwd-undo')?
}

Template.passphrase.events {
  'keyup #passphrase': (ev) ->
    if not Session.get('passphrase-setting')?
      return null

    passphrase = ev.srcElement.value
    storedHash = PpHashes.findOne {}, {}

    # check if entered passphrase is valid
    currentHash = CryptoJS.SHA3(passphrase).toString()

    if storedHash and (storedHash.pphash == currentHash)
      # TODO: is this secure?
      # if not, the passphrase needs to be stored in a custom reactive data
      # source, # see: http://docs.meteor.com/#meteor_deps
      Session.set 'pass', ev.srcElement.value
    else
      Session.set 'pass'

    null

  'click #button-passphrase-set': (ev, tmpl) ->
    Session.set 'passphrase-setting', true
    activateInput(tmpl.find('#passphrase'))
    null

  'click #button-passphrase-change': (ev, tmpl) ->
    Session.set 'passphrase-changing', true
    activateInput(tmpl.find('#passphrase'))
    null

  'click #button-delete-everything': (ev, tmpl) ->
    Session.set 'pass'
    Session.set 'passphrase-changing'
    Session.set 'search'
    Session.set 'passphrase-setting'
    Session.set 'passwd-undo'
    Meteor.call 'deleteEverything'
    tmpl.find('#passphrase').value = ''
}

changePassphrase = (newPp) ->
  oldPp = Session.get 'pass'
  Session.set 'pass', newPp
  deleteCurrentUndo()

  # TODO This operation is unsafe. If something crashes, the database
  # entries are fucked up. On solution would be versioning: Always keep the
  # old encrypted passwords and store the current version in the pphash 
  # collection
  if oldPp
    entries = Passwds.find {}, {}
    entries.forEach (entry) ->
      oldEncrypted = entry.password
      passObj = CryptoJS.Rabbit.decrypt(oldEncrypted, oldPp)
      newEncrypted = CryptoJS.Rabbit.encrypt(passObj, Session.get('pass')).toString()
      Passwds.update {'_id' : entry._id}, {'$set' : {'password':newEncrypted}}

  hash = CryptoJS.SHA3(newPp).toString()
  Meteor.call 'insertPpHash',
              hash

  null

Template.passphrase.helpers {
  validPassphrase: () ->
    Session.get('pass')?
  inputPassphrase: () ->
    Session.get('passphrase-setting')? or Session.get('passphrase-changing')?
  btnSetPassphrase: () ->
    not Session.get('passphrase-setting')? and not Session.get('pass')? and PpHashes.findOne()?
  passphraseError: () ->
    if not Session.get('pass')? and not Session.get('passphrase-changing')?
      'error'
    else
      ''
  btnChangePassphrase: () ->
    not Session.get('passphrase-changing')? and (Session.get('pass')? or not PpHashes.findOne()?)
  userId: @userId
}

Template.passphrase.events(okCancelEvents(
  '#passphrase',
  {
    ok: (value, ev) ->
      if Session.get('passphrase-setting')?
        Session.set 'passphrase-setting', null
        if not Session.get 'pass'
          ev.srcElement.value = ''
      else if Session.get('passphrase-changing')?
        Session.set 'passphrase-changing', null
        changePassphrase ev.srcElement.value
        ev.srcElement.value = Session.get 'pass'
      null
    cancel: (ev) ->
      if Session.get('passphrase-setting')?
        Session.set 'passphrase-setting', null
      else if Session.get('passphrase-changing')?
        Session.set 'passphrase-changing', null
        ev.srcElement.value = Session.get 'pass'
      null
  }
))



cellMetaData = (valuefunc, updatefunc, ispass) ->
  value = valuefunc()
  txtvalue =
    if value and ispass
      Array(value.length + 1).join '*'
    else
      value
  {
    txtvalue: txtvalue
    value: value
    ispass: if ispass then ispass else false
    _id: Meteor.uuid()
    updatefunc: updatefunc
  }

Template.passwdlist.helpers {
  entries: () ->
    search = Session.get 'search'
    if search and search != ''
      # TODO think about optimization. Regex in mongodb can be done on an index.
      regexp = new RegExp search, 'i'
      Passwds.find {'title':regexp}, {}
    else
      Passwds.find {}, {}

  passwdcelldecrypt: () ->
    cellMetaData () =>
        pass = Session.get 'pass'
        text =
          try
            if pass and pass != ''
              obj = CryptoJS.Rabbit.decrypt(@password, Session.get('pass'))
              obj.toString(CryptoJS.enc.Utf8)
            else
              null
          catch err
            null
      ,
      (newval) =>
        pass = Session.get 'pass'
        if pass and pass != ''
          encrypted = CryptoJS.Rabbit.encrypt(newval, pass).toString()
          generatePasswdUndo this, true
          Passwds.update {'_id': @_id}, {'$set': {'password': encrypted}}
      ,
      true


  passwdcelltitle: () ->
    cellMetaData () =>
        @title
      ,
      (newval) =>
        generatePasswdUndo this, true
        Passwds.update {'_id': @_id}, {'$set': {'title': newval}}
        null

  passwdcellusername: () ->
    cellMetaData () =>
        @username
      ,
      (newval) =>
        generatePasswdUndo this, true
        Passwds.update {'_id': @_id}, {'$set': {'username': newval}}
        null
}

Template.passwdlist.events {
  'click .trash': (ev) ->
    generatePasswdUndo this
    Passwds.remove {'_id': @_id}
    false
}

Meteor.startup () ->
  $('#button-passphrase-set').tooltip {
      title: 'enter passphrase in use'
      placement: 'bottom'
    }
  $('#button-passphrase-change').tooltip {
      title: 'set / change passphrase'
      placement: 'bottom'
    }
  $('#button-delete-everything').tooltip {
      title: 'delete all data'
      placement: 'bottom'
    }
  null

Template.new.events {
  'click #button-new': (ev, tmpl) ->
    deleteCurrentUndo()
    htmlTitle = tmpl.find('#new-title')
    htmlUsername = tmpl.find('#new-username')
    htmlPass = tmpl.find('#new-password')
    pass = htmlPass.value
    encrypted = CryptoJS.Rabbit.encrypt(pass, Session.get('pass')).toString()
    Meteor.call 'insertPasswd',
                htmlTitle.value,
                htmlUsername.value,
                encrypted

    htmlTitle.value = ''
    htmlUsername.value = ''
    htmlPass.value = ''

    null
  'keyup input' : (ev, tmpl) ->
    id = ev.srcElement.getAttribute('id')
    value = ev.srcElement.value
    if value == ''
      Session.set id
    else
      Session.set id, value
    null
}

Template.new.newEnabled = () ->
  Session.get('pass')? and _.all(
    Session.get(x)? for x in ['new-title', 'new-username', 'new-password'])
      

Template.passwdcell.events {
  'dblclick .cell' : (ev, tmpl) ->
    if @value
      Session.set 'editing_cell', @_id
      Meteor.flush()
      activateInput(tmpl.find('#cell-input'))
}

Template.passwdcell.editing = () ->
  Session.equals 'editing_cell', @_id

Template.passwdlist.events(okCancelEvents(
  '#cell-input',
  {
    ok: (value, ev) ->
      if value != @value and value != ''
        @updatefunc(value)
      Session.set 'editing_cell', null
    cancel: (ev) ->
      Session.set 'editing_cell', null
  }
))
