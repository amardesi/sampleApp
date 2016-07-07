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
# External gems we need
require 'cgi'
require 'digest'
require 'json'
require 'net/http'
require 'pp'
require 'sequel'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/cookies'
require 'unindent'
require 'yaml'

# Don't use Webrick, as sinatra-websocket requires 'thin', and 'thin' is better anyway.
set :server, 'thin'

# Flush stdout after each write, which makes debugging easier.
STDOUT.sync = true

###################################################################################################
# Use the Sequel gem to get connection pooling, thread safety, etc.
DB = Sequel.connect(YAML.load_file("config/database.yaml"))

###################################################################################################
# Model classes for interacting with the database
class Unit < Sequel::Model
  unrestrict_primary_key
end

class UnitHier < Sequel::Model(:unit_hier)
  unrestrict_primary_key
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
# Unit landing page
get "/unit/:unitID" do |unitID|
  unit = Unit[unitID]
  genAppPage("Unit landing page", request, { 
    :id => unitID,
    :name => unit.name,
    :type => unit.type,
    :parents => UnitHier.filter(:unit_id => unitID, :is_direct => true).map { |hier| hier.ancestor_unit },
    :children => UnitHier.filter(:ancestor_unit => unitID, :is_direct => true).map { |hier| hier.unit_id }
  })
end
