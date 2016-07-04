# GUI tool for working on eschol-specific parts of our OJS database

# Use bundler to keep dependencies local
require 'rubygems'
require 'bundler/setup'

###################################################################################################
# Use the right paths to everything, basing them on this script's directory.
def getRealPath(path) Pathname.new(path).realpath.to_s; end
$homeDir    = ENV['HOME'] or raise("No HOME in env")
$scriptDir  = getRealPath "#{__FILE__}/.."

###################################################################################################
# External code modules
require 'cgi'
require 'configparser'
require 'dbm'
require 'digest'
require 'fileutils'
require 'json'
require 'net/http'
require 'pp'
require 'rubyXL'
require 'sanitize'
require 'sequel'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/cookies'
require 'sinatra-websocket'
require 'unindent'
require 'yaml'

# Don't use Webrick, as sinatra-websocket requires thin
set :server, 'thin'

# Flush stdout after each write
STDOUT.sync = true

###################################################################################################
# Use the Sequel gem to get connection pooling, thread safety, etc.
conf = ConfigParser.new("#{$homeDir}/.passwords/ojs_db_pw.mysql")['mysql']
DB = Sequel.connect(:adapter=>'mysql2', 
                    :host=>conf['host'], :database=>conf['database'], 
                    :user=>conf['user'], :password=>conf['password'])

class User < Sequel::Model
  set_primary_key :user_id
  one_to_many :escholRoles
end

# eSchol roles table
class EscholRole < Sequel::Model
  many_to_one :user
end

###################################################################################################
# Need to retain session as a cookie so we can get usernames, and validate the user is logged in
# (except when fetching resources from /lib)
before do
  return if request.path =~ %r{^/(lib/|check)}
  # TODO
  #Thread.current[:cookies] = cookies
  #params['subiSession'] and cookies[:subiSession] = params['subiSession']
  #getSessionUsername() or halt(401, "Not authorized")
end

###################################################################################################
# If a cache buster comes in, strip it down to the original, and re-dispatch the request to return
# the actual file.
get %r{(.*)\._[0-9A-Z]{8}(\..*)} do
  call env.merge("PATH_INFO" => "#{params['captures'][0]}#{params['captures'][1]}")
end

###################################################################################################
# Transform a URL into a cache-busting URL that does the same thing.
$fileHashes = {}
def getFileHash(path)
  key = "#{path}:#{File.mtime(path)}"
  if !$fileHashes.include?(key)
    $fileHashes[key] = Digest::MD5.file(path).hexdigest.to_i(16).to_s(36)[0,8].upcase
  end
  return $fileHashes[key]
end

###################################################################################################
# Pick up all URLs in a string, and if they refer to a local file, change them to cache busters.
def cacheBustAll(htmlString)
  return htmlString.gsub(%r{(href|src)="([^"]+)"}) { |m|
    attrib, url = $1, $2
    path = "#{File.dirname(__FILE__)}/public/#{url}"
    File.exist? path and url.sub!(/\.[^\.]+$/, "._#{getFileHash(path)}\\0")
    "#{attrib}=\"#{url}\""
  }
end

###################################################################################################
def isoFetch(request, pageName, initialData)
  request.url =~ %r{^https?://([^/:]+)} or fail
  host = $1
  req = Net::HTTP::Post.new("/#{pageName}", initheader = {'Content-Type' =>'application/json'})
  req.body = initialData.to_json
  response = Net::HTTP.new(host, 4002).start {|http| http.request(req) }
  response.code == "200" or fail
  return response.body
end

###################################################################################################
# The outer framework of every page is exactly the same.
def genAppPage(title, request, initialData)
  root = request.path_info.gsub(%r{[^/]+}, '..').sub(%r{^/../..}, '../').sub(%r{/..}, '')
  pageName = request.path_info.sub(%r{^/}, '').sub(%r{/.*$}, '')

  # Most of the boilerplate below is directly from Bootstrap's recommended framework
  return cacheBustAll(%{
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="x-ua-compatible" content="ie=edge">
        <title>#{CGI.escapeHTML(title)}</title>
        <link rel="stylesheet" href="#{root}lib/bootstrap/dist/css/bootstrap.css">
        <link rel="stylesheet" href="#{root}lib/tether/dist/css/tether.css"> <!-- needed by bootstrap -->
        <link rel="stylesheet" href="#{root}css/global.css">
        #{File.exist?("public/css/#{pageName}.css") ? "<link rel=\"stylesheet\" href=\"#{root}css/#{pageName}.css\">" : ""}
        <script src="#{root}lib/jquery/dist/jquery.min.js"></script>
        <script src="#{root}lib/underscore/underscore.js"></script>
        <script src="#{root}lib/tether/dist/js/tether.js"></script> <!-- needed by bootstrap -->
        <script src="#{root}lib/iframe-resizer/js/iframeResizer.contentWindow.js"></script>
      </head>
      <body>
        <script>
          initialData = #{initialData.to_json};
        </script>
        <div id="uiBase">#{isoFetch(request, pageName, initialData)}</div>
        <script src="#{root}lib/react/react.js"></script>
        <script src="#{root}lib/react/react-dom.js"></script>
        <script src="#{root}js/global.js"></script>
        #{File.exist?("public/js/#{pageName}.js") ? "<script src=\"#{root}js/#{pageName}.js\"></script>" : ""}
        <script src="#{root}lib/bootstrap/dist/js/bootstrap.js"></script>
      </body>
    </html>
  }).unindent
end

###################################################################################################
def returnApiData(params, result)
  if params['init']
    content_type :js
    "initialData = #{result.to_json}"
  else
    content_type :json
    result.to_json
  end
end

###################################################################################################
# Up-ness check so 'eye' can tell we're running
get "/check" do
  "batchImpExp running"
end

###################################################################################################
# Batch operations page
get "/batchOps" do
  genAppPage("Batch Operations", request, { :entity => params['entity'] })
end
