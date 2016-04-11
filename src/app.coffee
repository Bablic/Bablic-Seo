express = require 'express'
app = express()
request = require 'request'
crypto = require 'crypto'
OS = require 'os'
fs = require 'fs'
async = require 'async'
moment = require 'moment'


#http://dev.bablic.com/api/engine/seo?site=56e7e95e374c81ab110e4cb4&url=http://lemonberry.com/?locale=es

#<middleware>

BablicSeo = (options) ->
  if options.default_cache?
    console.log 'setting timeout'
    setTimeout ->
      console.log 'starting preloads'
      preload()
    , 1500

  preload = ->
    preloads = []
    for url in options.default_cache
      preloads.push ->
        get_html url, null, (error, data) ->
          if error?
            console.error "[Bablic SDK] Error: url #{url} failed preloading"
            console.error error
          else
            console.log "[Bablic SDK] - Preload #{url} complete, size: #{data.length}"

    async.series preloads
    return

  get_html = (url, html, cbk) ->
    ops =
      url: "http://dev.bablic.com/api/engine/seo?site=#{options.site_id}&url=#{url}"
      method: 'POST'
      json: true
      body:
        html: html
    request ops, (error, response, body) ->
      if error?
        return cbk error
      fs.writeFile full_path_from_url(url), body, (error) ->
        if error
          return cbk error
        cbk null, body
      return

  hash = (data) -> crypto.createHash('md5').update(data).digest('hex')

  full_path_from_url = (url) -> OS.tmpdir()+'/'+ hash(url)

  cache_valid = (file_stats) ->
    last_modified = moment file_stats.mtime.getTime()
    now = moment()
    last_modified.add 30, 'minutes'
    return now.isBefore(last_modified)

  get_from_cache = (url, callback) ->
    file_path = full_path_from_url(url)
    fs.stat file_path, (error, file_stats) ->
      if error?
        return callback {
          errno: 1
          msg: 'does not exist in cache'
        }
      fs.readFile file_path, (error, data) ->
        if error?
          error =
            errno: 2
            msg: 'error reading from FS'
        else unless cache_valid(file_stats)
          error = {
            errno: 3
            msg: 'cache not valid'
          }
        callback error, data
    return null

  ignorable = (req) ->
    filename_tester = /\.(js|css|jpg|jpeg|png|mp3|avi|mpeg|bmp|wav|pdf|doc|xml|docx|xlsx|xls|json|kml|svg|eot|woff|woff2)/
    return filename_tester.test req.url

  is_bot = (req) ->
    google_tester = new RegExp /bot|crawler|baiduspider|80legs|mediapartners-google|adsbot-google/i
    return google_tester.test req.headers['user-agent']

  should_handle = (req, res) ->
    #TODO: add content type check for text/html
    return is_bot(req) and not ignorable(req)

  return (req, res, next) ->
    if should_handle(req, res)
      my_url = "http://#{req.headers.host}#{encodeURIComponent(req.url)}"
      my_url = 'http://bablic.weebly.com/?locale=fr'
      get_from_cache my_url, (error, data) ->
        cache_only = false
        if data?
          console.log 'sending from cache->', data.toString().length
          res.write(data)
          res.end()
          cache_only = true
          return unless error?
        res._end = res.end
        res._write = res.write
        html = ''
        res.write = (new_html) -> html+= new_html
        res.end = ->
          get_html my_url, html, (error, data) ->
            return res._end() if cache_only
            if error?
              console.error '[Bablic SDK] Error:', error
              res._write html
              res._end()
              return
            console.log 'sending from bablic->'
            res._write data
            res._end()
            return
          return
        return next()
      return next()
    return next()

#TODO:
# 1. readfile, get_from_cache -DONE
# 2. sending html in post - DONE
# 3. deliver from cache if exist but if cache > 30m refresh it lazily.

options =
  site_id: '5704e06335b0a72b75ca3e1c'
  TTL: 2
  default_cache: ['http://bablic.weebly.com/?locale=fr']

app.use BablicSeo(options)

#</middleware>

app.get '/', (req, res) ->
  res.write 'About'
  console.log 'sent no'
  res.end()

app.listen 81

