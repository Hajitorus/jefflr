# Required Modules
http = require('http')
fs = require('fs')
request = require('request')
querystring = require('querystring')
websock = require('ws')
irc = require('irc')

# General bot configuration
ircNick = "devvlrbot"
ircChannel = "#jeffdevs"
ircServer = "irc.freenode.org"
channelId = 27902
userAgent = "mixirc <3"

userList = {}
ignoreList = []

useFirebase = true

if useFirebase
	firebase = require('firebase')
	auth = require('./auth.json')
	# New proof of concept firebase thingy.
	firebaseDomain = "https://blazing-fire-3008.firebaseio.com/"
	db = new firebase(firebaseDomain)
	db.auth auth.token, (error) ->
		if error
			console.log "[FAIL] Firebase Authication: ", error
		else
			console.log "[PASS] Firebase Authenticated"
	dataRef = new firebase(firebaseDomain)
	dataRef.on 'value', (snapshot) ->
		db = snapshot.val()
		ircNick = db.config.ircNick
		ircChannel = db.config.ircChannel
		ircServer = db.config.ircServer
		channelId = db.config.channelId
		userAgent = db.config.userAgent
		ignoreList = db.ignoreList
		userList = db.users

else
	# This should be replaced by a dict of prod/bob/haji that lets you select
	# See http://api.mixlr.com/users/jeff-gerstmann for example channelId ("id")
	botDefaults = 
		ircNick: "jefflrbot"
		ircChan: "#JeffDrives"
		ircServ: "irc.freenode.org"
		mixChan: 27902

	botPersonalities =
		"jefflr2":
			ircNick: "jefflrbot2"
			ircChan: "#JeffDrives2"
		"haji":
			ircNick: "devvlrbot"
			ircChan: "#JeffDevs"

	for name, opts in botPersonalities when process.argv is name
		for key, val in opts
			botDefaults[key] = val

	# Won't Mixlr => IRC relay if from these usernames
	ignoreList = [
		"Minnie Marabella",
		"WERD SLLIM"
	]
	# Ideally:
	# .info minnie
	# -> jefflr returns a minnie infospiel, including uid
	# .ignore uid
	# -> jefflr fucks off the uid and all aliases

	# Users for IRC => Mixlr relay
	userList =
		"BobBarker":
			"mixlrUserLogin": ""
			"mixlrAuthSession": ""
			"canHeart": true
		"Hajitorus":
			"mixlrUserLogin": ""
			"mixlrAuthSession": ""
			"canHeart": true

# Creates the IRC client with given params
ircBot = new irc.Client botDefaults.ircServer, botDefaults.ircNick,
	password: null,
	userName: botDefaults.ircNick,
	realName: botDefaults.ircNick,
	port: 6667,
	debug: false,
	showErrors: false,
	autoRejoin: true,
	autoConnect: true,
	channels: [botDefaults.ircChannel],
	retryCount: null,
	retryDelay: 2000,
	secure: false,
	selfSigned: false,
	certExpired: false,
	floodProtection: true,
	floodProtectionDelay: 200,
	sasl: false,
	stripColors: false,
	channelPrefixes: "&#",
	messageSplit: 512

ircInitBot = ->
	ircBot.addListener 'message', (from, to, message) ->
		console.log '%s => %s: %s', from, to, message
		return if from is ircBot.nick
		for user, info of userList
			continue unless from == user
			if message.toLowerCase() is "sup " + ircBot.nick
				ircBot.say to, "OH YOU KNOW JUST ENSLAVING THE HUMAN RACE"
			# NOTE: The Regex below only returns true if the message is ".#"
			# (# = number of any size)
			else if (/^(\.[0-9]+)$/.test message) and info.canHeart
				commentId = message.replace ".", ""
				console.log "IRC => postAddCommentHeart: ", user, commentId,
					message, botDefaults.mixChan, info.mixlrUserLogin, info.mixlrAuthSession
				postAddCommentHeart commentId, info
			else
				console.log "IRC => postComm: ", user, message, botDefaults.mixChan,
					info.mixlrUserLogin, info.mixlrAuthSession
				postComm message, botDefaults.mixChan, info

sendHTTP = (httpHeader, data) ->
	httpReq = http.request httpHeader, (res) ->
		res.setEncoding('UTF-8')
	# Send HTTP POST
	httpReq.write data
	httpReq.end()

# Forms HTTP headers and data for IRC => Mixlr comment relay, sends to sendHTTP.
postComm = (comment, channelId, user) ->
	data = querystring.encode
		"comment[content]": comment,
		"comment[broadcaster_id]": channelId,
	# An object of options to indicate where to post to
	httpHeader =
		hostname: 'mixlr.com'
		path: '/comments'
		method: 'POST'
		headers:
			"X-Requested-With": "XMLHttpRequest"
			"User-Agent": userAgent
			"Content-type": "application/x-www-form-urlencoded"
			"Accept": 'text/plain'
			"Cookie": 'mixlr_user_login=' + user.mixlrUserLogin +
				'; mixlr_session=' + user.mixlrAuthSession
	console.log "postComm => Mixlr: ", comment, httpHeader, data,
		user.mixlrUserLogin, user.mixlrAuthSession
	# Send HTTP POST
	sendHTTP httpHeader, data

# Forms HTTP headers and data for IRC => Mixlr comment hearting, sends to sendHTTP.
postAddCommentHeart = (commentId, user) ->
	console.log "postAddCommentHeart =>", commentId, user
	httpHeader =
		hostname: "mixlr.com"
		path: "/comments/"+commentId+"/heart"
		method: "POST"
		headers:
			"X-Requested-With": "XMLHttpRequest"
			"User-Agent": userAgent
			"Content-Type": "application/x-www-form-urlencoded"
			"Accept": "text/plain"
			"Cookie": "mixlr_user_login=" + user.mixlrUserLogin +
				"; mixlr_session=" + user.mixlrAuthSession
	console.log httpHeader
	# Send HTTP POST
	sendHTTP httpHeader, ""

# Opens a websocket connection and receives data as long as the connection remains open
# TODO: add in the ping function (seems to be every 5 minutes)
openSock = (channelId) ->
	broadcastStart = false
	channelSocket = JSON.stringify
		"event":
			"pusher:subscribe"
		"data":
			"channel":
				"production;user;"+channelId
	
	ws = new websock 'ws://ws.pusherapp.com/app/2c4e9e540854144b54a9?protocol=5&client=js&version=1.12.7&flash=false'

	ws.on 'open', ->
		console.log "Connected."
		ws.send channelSocket

	ws.on 'message', (message) ->
		console.log 'Received: %s', message
		try
			m = JSON.parse message
		catch err
			console.log "JSON.parse(message) failed: " + err.message
		switch m.event
			when "comment:created"
				try
					# NOTE: decodeURIComponent() will throw an exception if it finds
					# an unencoded '%' character, unescape does not.
					#a = JSON.parse(decodeURIComponent(m.data))
					a = JSON.parse unescape m.data
				catch err
					console.log "JSON.parse(unescape(m.data)) failed: #{ err.message }"
				if ignoreList.indexOf a.name is -1
					try
						id = a.id
						ircSay = irc.colors.wrap "light_gray", "["
						ircSay += irc.colors.wrap "light_green", a.name
						ircSay += irc.colors.wrap "light_gray", "]: "
						ircSay += irc.colors.wrap "yellow", a.content
						ircSay += irc.colors.wrap "light_gray", " ["+id+"]"
						ircBot.say botDefaults.ircChannel, ircSay
					catch err
						ircBot.say botDefaults.ircChannel, err.message
						console.log "ircBot.say failed: "+err.message
				else
					console.log "Ignored: "+a.name+" : "+a.content

			when "broadcast:start"
				if broadcastStart is false
					broadcastStart = true
					ircBot.say botDefaults.ircChannel, "STREAM IS LIVE: http://mixlr.com/jeff-gerstmann/chat/"

			when "comment:hearted"
				a = JSON.parse (unescape m.data)
				# TODO make this pretty, show original comment and translate
				# user_ids into names.
				ircSay = irc.colors.wrap("light_magenta", "<3 ")
				ircSay += irc.colors.wrap("light_blue", a.user_ids+" ")
				ircSay += irc.colors.wrap "light_red", a.comment_id
				ircBot.say(botDefaults.ircChannel, ircSay)

	ws.on 'close', ->
		console.log "WebSocket Closed"

# Starts up the IRC bot according to above config
ircInitBot()

# Opens a websocket connection, given the params below
openSock botDefaults.mixChan

# vim: set noet ts=4:
