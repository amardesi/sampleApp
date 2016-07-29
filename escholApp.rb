# Sample application foundation for eschol5 - see README.md for more info

# Use bundler to keep dependencies local
require 'rubygems'
require 'bundler/setup'

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
# Use the Sequel gem to get object-relational mapping, connection pooling, thread safety, etc.
DB = Sequel.connect(YAML.load_file("config/database.yaml"))

###################################################################################################
# Model classes for easy interaction with the database.
#
# For more info on the database schema, see contents of migrations/ directory, and for a more
# graphical version, see:
#
# https://docs.google.com/drawings/d/1gCi8l7qteyy06nR5Ol2vCknh9Juo-0j91VGGyeWbXqI/edit

class Unit < Sequel::Model
  unrestrict_primary_key
end

class UnitHier < Sequel::Model(:unit_hier)
  unrestrict_primary_key
end

###################################################################################################
# CACHE BUSTING
# =============
#
# Browsers like to cache stuff, and unfortunately they're not always good about checking whether
# their cache is actually up to date. This can be especially annoying for CSS and Javascript
# changes.
#
# To prevent the browser from ever using an out-of-date asset, we implement a system of "cache
# busting" here. Here are the steps:
#
#  1. When we generate an HTML page, a piece of code (cacheBustAll below) scans the HTML for
#     links to likely assets.
#  2. Each link is modified to include a unique code based on the actual contents of the file.
#     E.g. "escholarship_small.png" becomes "escholarship_small._7M0FWEK4.png"
#  3. When requests come from the browser for an asset, we look for the pattern of the cache-
#     busting addition, strip it off, and grab the file based on the original name.
#
# In this way, when a file changes, we'll start generating a different coded filename for it,
# and browsers will not match it in their cache and will ask for a new copy.
###################################################################################################

###################################################################################################
# If a cache buster comes in, strip it down to the original, and re-dispatch the request to return
# the actual file.
get %r{(.*)\._[0-9A-Z]{8}(\..*)} do  # tricky regular exp. to spot things like "filename._7M0FWEK4.png"
  # Sinatra's "call" function re-dispatches the request with modifications.
  call env.merge("PATH_INFO" => "#{params['captures'][0]}#{params['captures'][1]}")
end

###################################################################################################
# Transform a URL into a cache-busting URL that does the same thing.
$fileHashes = {}  # global cache of hashes; good enough for now.
def getFileHash(path)
  key = "#{path}:#{File.mtime(path)}"
  # If we haven't seen this file with this timestamp, add it to our cache.
  if !$fileHashes.include?(key)
    # A bit of obtuse logic to calculate the file's hash, and represent it in only 8 letters and numbers.
    $fileHashes[key] = Digest::MD5.file(path).hexdigest.to_i(16).to_s(36)[0,8].upcase
  end
  return $fileHashes[key]
end

###################################################################################################
# Pick up all URLs in a string, and if they refer to a local file, change them to cache busters.
def cacheBustAll(htmlString)
  # Look for all href="blah" or src="blah" URLs, and cache-bust them.
  return htmlString.gsub(%r{(href|src)="([^"]+)"}) { |m|
    attrib, url = $1, $2
    # Only fiddle with URLs that refer to real files.
    path = "#{File.dirname(__FILE__)}/public/#{url.sub(%r{^\.*/}, "")}"
    File.exist? path and url.sub!(/\.[^\.]+$/, "._#{getFileHash(path)}\\0")
    "#{attrib}=\"#{url}\""
  }
end

###################################################################################################
# ISOMORPHIC JAVASCRIPT
# =====================
#
# Using a Javascript front-end framework like React has a couple downsides: First, it makes the
# site unusable by users who have Javascript turned off. Second, not all crawlers can or do run
# your javascript, and so it might make the site invisible to them.
#
# The solution is so-called "isomorphic Javascript". Basically we run React not only in the
# browser but also on the server. When the page initially loads, we generate the initial HTML
# that React will eventually generate once it fully initializes on the client side, and we send
# that HTML as a starting point. When React starts up on the client, it verifies that the HTML
# is the same (and issues a console warning if not).
#
# How do we run React on the server? We keep a little Node Express server running on a differnet
# port than the main app, and when we need to load a page we feed it the initial data, it runs
# the appropriate React templates, and returns us the HTML. See 
#
# In this way, the user gets a speedy initial load, can use some of the site features without
# javascript, and crawlers have an easy time seeing everything the users see.
###################################################################################################

###################################################################################################
def isoFetch(request, pageName, initialData)
  # We need to grab the hostname from the URL. There's probably a better way to do this.
  request.url =~ %r{^https?://([^/:]+)} or fail
  host = $1

  # Post the initial data to our little Node Express app, which will run it through React.
  req = Net::HTTP::Post.new("/#{pageName}", initheader = {'Content-Type' =>'application/json'})
  req.body = initialData.to_json
  response = Net::HTTP.new(host, 4002).start {|http| http.request(req) }
  response.code == "200" or fail

  # Return the resulting HTML
  return response.body
end

###################################################################################################
# The outer framework of every page is essentially the same, with tiny variations.
def genAppPage(title, request, initialData)
  # A bit of obtuse parsing to figure out the name of the page being requested.
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
# Unit landing page. After the slash is the unit_id.
get "/unit/:unitID" do |unitID|
  unit = Unit[unitID]
  
  # Initial data for the page consists of the unit's id, name, type, etc. plus lists of the unit's
  # children and parents drawn from the unit_hier database table. Remember that "direct" links are
  # direct parents and children. "Indirect" (which we don't use here) are for grandparents/ancestors,
  # and grand-children/descendants.
  genAppPage("Unit landing page", request, { 
    :id => unitID,
    :name => unit.name,
    :type => unit.type,
    :parents => UnitHier.filter(:unit_id => unitID, :is_direct => true).map { |hier| hier.ancestor_unit },
    :children => UnitHier.filter(:ancestor_unit => unitID, :is_direct => true).map { |hier| hier.unit_id }
  })
end

###################################################################################################
# Item view page.
get "/uc/item/:shortArk" do |shortArk|
  item = Item["qt"+shortArk]
  
  # FIXME: Martin make this work
end
