http = require 'http'
express = require 'express'
coffeecup = require 'coffeecup'

app = express()
app.set('view engine', 'coffee')
app.engine 'coffee', require('coffeecup').__express

user = 'jeff-gerstmann'

getShowreel = (user, page, callback) ->

	showreelPath = '/'
	showreelPath += user
	showreelPath += '/showreel/?page='
	showreelPath += page.toString()

	options = {
		hostname: 'mixlr.com',
		port: 80,
		path: showreelPath,
		method: 'GET'
	}

	req = http.request options, (res) ->
		data = ''
		res.setEncoding('utf8')
		res.on 'data', (chunk) ->
			data += chunk
		res.on 'end', () ->
			startStr = data.indexOf "broadcasterData", 0
			lastStr = data.indexOf "}];", startStr
			evalData = "var "
			evalData += data.slice startStr, lastStr+3
			eval (evalData)
			callback { broadcasts, broadcasterData }
	req.end()

app.get '/', (req, res) ->
	page = 1
	getShowreel user, page, (broadcasts, broadcasterData) ->
		indexTitle = 'Jeffreel'
		res.render 'index', broadcasts, broadcasterData, pageName = indexTitle

app.listen 3000

console.log "Listening on 3000..."