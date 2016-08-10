#!/usr/bin/env ruby

# This script converts data from old eScholarship into the new eschol5 database.
# It should generally be run on a newly cleaned-out database. This sequence of commands
# should do the trick:
#
# bin/sequel config/database.yaml -m migrations/ -M 0 && \
# bin/sequel config/database.yaml -m migrations/ && \
# ./convert.rb /path/to/allStruct.xml

# Use bundler to keep dependencies local
require 'rubygems'
require 'bundler/setup'

# Remainder are the requirements for this program
require 'date'
require 'json'
require 'nokogiri'
require 'open3'
require 'pp'
require 'sequel'
require 'time'
require 'yaml'

MAX_BATCH_SIZE = 50   # small for now, 1 thing per batch

# Connect to the databases we'll use
QUEUE_DB = Sequel.connect(YAML.load_file("config/queueDb.yaml"))
DB = Sequel.connect(YAML.load_file("config/database.yaml"))

# Queues for thread coordination
$prefilterQueue = SizedQueue.new(100)
$indexQueue = SizedQueue.new(100)

# Make puts thread-safe
$stdoutMutex = Mutex.new
def puts(*args)
  $stdoutMutex.synchronize { 
    Thread.current[:name] and STDOUT.write("[#{Thread.current[:name]}] ")
    super(*args) 
  }
end

###################################################################################################
# Monkey patches to make Nokogiri even more elegant
class Nokogiri::XML::Node
  def text_at(xpath)
    at(xpath) ? at(xpath).text : nil
  end
end

###################################################################################################
# Model classes for easy object-relational mapping in the database

class Unit < Sequel::Model
  unrestrict_primary_key
end

class UnitHier < Sequel::Model(:unit_hier)
  unrestrict_primary_key
end

class Item < Sequel::Model
  unrestrict_primary_key
end

class UnitItem < Sequel::Model
  unrestrict_primary_key
end

class ItemAuthor < Sequel::Model
  unrestrict_primary_key
end

class Issue < Sequel::Model
end

class Section < Sequel::Model
end

###################################################################################################
# Insert hierarchy links (skipping dupes) for all descendants of the given unit id.
def linkUnit(id, childMap, done)
  childMap[id].each_with_index { |child, idx|
    if !done.include?([id, child])
      #puts "linkUnit: id=#{id} child=#{child}"
      UnitHier.create(
        :ancestor_unit => id,
        :unit_id => child,
        :ordering => idx,
        :is_direct => true
      )
      done << [id, child]
    end
    if childMap.include?(child)
      linkUnit(child, childMap, done)
      linkDescendants(id, child, childMap, done)
    end
  }
end

###################################################################################################
# Helper function for linkUnit
def linkDescendants(id, child, childMap, done)
  childMap[child].each { |child2|
    if !done.include?([id, child2])
      #puts "linkDescendants: id=#{id} child2=#{child2}"
      UnitHier.create(
        :ancestor_unit => id,
        :unit_id => child2,
        :ordering => nil,
        :is_direct => false
      )
      done << [id, child2]
    end
    if childMap.include?(child2)
      linkDescendants(id, child2, childMap, done)
    end
  }
end

###################################################################################################
# Convert an allStruct element, and all its child elements, into the database.
def convertUnits(el, parentMap, childMap)
  id = el[:id] || el[:ref] || "root"
  #puts "name=#{el.name} id=#{id.inspect} name=#{el[:label].inspect}"

  # Handle regular units
  if el.name == "allStruct"
    Unit.create(
      :id => "root",
      :name => "eScholarship",
      :type => "root",
      :is_active => true,
      :attrs => nil
    )
  elsif el.name == "div"
    attrs = {}
    el[:directSubmit] and attrs[:directSubmit] = el[:directSubmit]
    el[:hide]         and attrs[:hide]         = el[:hide]
    Unit.create(
      :id => id,
      :name => el[:label],
      :type => el[:type],
      :is_active => el[:directSubmit] != "moribund",
      :attrs => JSON.generate(attrs)
    )
  elsif el.name == "ref"
    # handled elsewhere
  end

  # Now recursively process the child units
  el.children.each { |child|
    if child.name != "allStruct"
      id or raise("id-less node with children")
      childID = child[:id] || child[:ref]
      childID or raise("id-less child node")
      parentMap[childID] ||= []
      parentMap[childID] << id
      childMap[id] ||= []
      childMap[id] << childID
    end
    convertUnits(child, parentMap, childMap)
  }

  # After traversing the whole thing, it's safe to form all the hierarchy links
  if el.name == "allStruct"
    puts "Linking units."
    linkUnit("root", childMap, Set.new)
  end
end

###################################################################################################
def prefilterBatch(batch)

  # Build a file with the relative directory names of all the items to prefilter in this batch
  open("prefilterDirs.txt", "w") { |io|
    batch.each { |itemID|
      shortArk = itemID.sub(%r{^ark:/?13030/}, '')
      io.puts "13030/pairtree_root/#{shortArk.scan(/\w\w/).join('/')}/#{shortArk}"
    }
  }

  # Run the XTF textIndexer in "prefilterOnly" mode. That way the stylesheets can do all the
  # dirty work of normalizing the various data formats, and we can use the uniform results.
  puts "Running prefilter batch of #{batch.size} items."
  cmd = ["/apps/eschol/erep/xtf/bin/textIndexer", 
         "-prefilterOnly",
         "-force",
         "-dirlist", "#{Dir.pwd}/prefilterDirs.txt",
         "-index", "eschol5"]
  Open3.popen2e(*cmd) { |stdin, stdoutAndErr, waitThread|
    stdin.close()

    # Process each line, looking for BEGIN prefiltered ... END prefiltered
    shortArk, buf = nil, []
    outer = []
    stdoutAndErr.each { |line|
      if line =~ %r{>>> BEGIN prefiltered.*/(qt\w{8})/}
        shortArk = $1
      elsif line =~ %r{>>> END prefiltered}
        # Found a full block of prefiltered data. This item is ready for indexing.
        $indexQueue << [shortArk, buf.join]
        shortArk, buf = nil, []
      elsif shortArk
        buf << line
      else
        outer << line
      end
    }
    waitThread.join
    if not waitThread.value.success?
      puts outer.join
      raise("Command failed with code #{waitThread.value.exitstatus}")
    end
    File.delete "prefilterDirs.txt"
  }
end

###################################################################################################
def prefilterAll
  Thread.current[:name] = "prefilter thread"  # label all stdout from this thread
  batch = []
  loop do
    itemID = $prefilterQueue.pop
    itemID or break
    batch << itemID
    if batch.size >= 50
      prefilterBatch(batch)
      batch = []
    end
  end
  batch.empty? or prefilterBatch(batch)
  $indexQueue << [nil, nil] # end-of-work
end

###################################################################################################
def traverseText(node, buf)
  return if node['meta'] == "yes" || node['index'] == "no"
  node.text? and buf << node.to_s.strip + "\n"
  node.children.each { |child| traverseText(child, buf) }
end

###################################################################################################
def emptyBatch(batch)
  batch[:items] = []
  batch[:idxData] = "["
  batch[:idxDataSize] = 0
  return batch
end

###################################################################################################
def indexItem(itemID, prefilteredData, batch)
  prefilteredData.sub! "<erep-article>", "<erep-article xmlns:xtf=\"http://cdlib.org/xtf\">"
  puts "#{itemID}"

  # Parse the metadata (and toss the namespaces; they just make things harder to code)
  data = Nokogiri::XML(prefilteredData, &:noblanks)
  data.remove_namespaces!

  data = Class.new {
    def initialize(prefilteredData)
      doc = Nokogiri::XML(prefilteredData, &:noblanks)
      doc.remove_namespaces!
      @root = doc.root
    end

    def single(name)
      els = @root.xpath("meta/#{name}[@meta='yes']")
      els.length <= 1 or puts("Warning: multiple #{name.inspect} elements found.")
      return els[0] ? els[0].text : nil
    end

    def multiple(name)
      return @root.xpath("meta/#{name}[@meta='yes']").map { |el| el.text }
    end

    def any(name)
      return @root.xpath("meta/#{name}[@meta='yes']").length > 0
    end

    def root
      return @root
    end    
  }.new(prefilteredData)

  attrs = {}
  data.single("contentExists") == "yes" and attrs[:contentExists] = true
  data.single("pdfExists"    ) == "yes" and attrs[:pdfExists] = true
  data.single("peerReview"   ) == "yes" and attrs[:peerReviewed] = true
  data.single("language"     )          and attrs[:language] = data.single("language")
  data.any("facet-discipline")          and attrs[:disciplines] = data.multiple("facet-discipline")

  # Filter out "n/a" abstracts
  data.single("description") && data.single("description").size > 3 and attrs[:abstract] = data.single("description")

  # Populate the Item model instance
  dbItem = Item.new
  dbItem[:id]           = itemID
  dbItem[:source]       = data.single("source")
  dbItem[:status]       = data.single("pubStatus") || "unknown",
  dbItem[:title]        = data.single("title"),
  dbItem[:content_type] = data.single("format"),
  dbItem[:genre]        = data.single("type"),
  dbItem[:pub_date]     = data.single("date") || "1901-01-01",
  dbItem[:eschol_date]  = data.single("datestamp") || "1901-01-01", #FIXME: Think about this carefully. What's eschol_date for?
  dbItem[:rights]       = data.single("rights") || "public",
  dbItem[:attrs]        = JSON.generate(attrs)

  # Populate ItemAuthor model instances
  dbAuthors = data.multiple("creator").each_with_index { |name, idx|
    ItemAuthor.new { |auth|
      auth[:item_id] = itemID
      auth[:attrs] = JSON.generate({name: name})
      auth[:ordering] = idx
    }
  }

  # For eschol journals, populate the issue and section models.
  issue = section = nil
  if data.single("pubType") == "journal"
    issue = Issue.new
    issue[:unit_id] = data.single("entityOnly")
    issue[:volume]  = data.single("volume")
    issue[:issue]   = data.single("issue")
    issue[:pub_date] = data.single("date") || "1901-01-01"

    section = Section.new
    section[:name]  = data.single("sectionHeader") ? data.single("sectionHeader") : "default"
    section[:order] = data.single("document-order") ? data.single("document-order") : 1
  end

  # Process all the text nodes
  text = ""
  traverseText(data.root, text)

  # Create JSON for the full text index
  idxItem = {
    type:          "add",   # in CloudSearch land this means "add or update"
    id:            itemID,
    fields: {
      title:         dbItem[:title] || "",
      authors:       data.multiple("creator"),
      abstract:      attrs[:abstract] || "",
      content_types: data.multiple("format"),
      disciplines:   attrs[:disciplines] ? attrs[:disciplines].map { |ds| ds[/^\d+/] } : [""], # only the numeric parts
      peer_reviewed: attrs[:peerReviewed] ? 1 : 0,
      pub_date:      "#{dbItem[:pub_date]}T00:00:00Z",
      pub_year:      dbItem[:pub_date][/^\d\d\d\d/],
      rights:        dbItem[:rights],
      sort_author:   (data.multiple("creator")[0] || "").gsub(/[^\w ]/, '').downcase,
      units:         data.multiple("facet-fullAffil").map { |fa| fa.sub(/.*::/, "") },
      text:          text
    }
  }
  idxData = JSON.generate(idxItem)

  # If this item won't fit in the current batch, send that batch off.
  if batch[:idxDataSize] + idxData.size > MAX_BATCH_SIZE
    puts "Considering batch with #{batch[:items].size} items."
    batch[:items].empty? or processBatch(batch)
    emptyBatch(batch)
  end

  # Now add this item to the batch
  batch[:items].empty? or batch[:idxData] << ",\n"  # Separator between records
  batch[:idxData] << idxData
  batch[:idxDataSize] += idxData.size
  batch[:items] << { dbItem: dbItem, dbAuthors: dbAuthors, dbIssue: issue, dbSection: section }
  puts "data size: #{batch[:idxDataSize]}"
end

###################################################################################################
def indexAll
  Thread.current[:name] = "index thread"  # label all stdout from this thread
  batch = emptyBatch({})
  loop do
    itemID, prefilteredData = $indexQueue.pop
    itemID or break
    indexItem(itemID, prefilteredData, batch)
  end
  batch.items.empty? or processBatch(batch)
end

###################################################################################################
def processBatch(batch)

  # Finish the data buffer, and send to AWS
  batch[:idxData] << "]"

#curl -X POST --upload-file movie-data-2013.json doc-movies-123456789012.us-east-1.cloudsearch.amazonaws.com/2013-01-01/documents/batch --header "Content-Type:application/json"
  url = "http:///2013-01-01/documents/batch"
  host = "doc-eschol5-test-u5sqhz5emqzdh4bfij7uxsazny.us-west-2.cloudsearch.amazonaws.com"
  puts "Posting #{batch[:idxDataSize]} characters of data."
  puts batch[:idxData]
  req = Net::HTTP::Post.new("/2013-01-01/documents/batch", initheader = {'Content-Type' =>'application/json'})
  req.body = batch[:idxData]
  response = Net::HTTP.new(host, 80).start {|http| http.request(req) }
  puts "response: #{response}"
  puts response.body
  response.code == "200" or fail
  exit 1
end

###################################################################################################
# Convert one item
def convertItem(doc)

  # First the item itself
  id = doc.text_at("identifier")
  attrs = {}
  doc.text_at("contentExists") == "yes" and attrs[:contentExists] = true
  doc.text_at("pdfExists") == "yes" and attrs[:pdfExists] = true
  doc.text_at("language") and attrs[:language] = doc.text_at("language")
  doc.text_at("peerReview") == "yes" and attrs[:peerReviewed] = true
  Item.create(
    :id => id,
    :source => doc.text_at("source"),
    :status => doc.text_at("pubStatus") || "unknown",
    :title => doc.text_at("title"),
    :content_type => doc.text_at("format"),
    :genre => doc.text_at("type"),
    :pub_date => doc.text_at("date") || "1901-01-01",
    :eschol_date => doc.text_at("dateStamp") || "1901-01-01", #FIXME
    :attrs => JSON.generate(attrs),
    :rights => doc.text_at("rights") || "public"
  )

  # Link the item's authors
  doc.text_at("creator") and doc.text_at("creator").split(";").each_with_index { |auth, order|
    attrs = {}
    if auth.split(",").length == 2
      attrs[:lname], attrs[:fname] = auth.split(/\s*,\s*/)
    else
      attrs[:organization] = auth
    end
    ItemAuthor.create(
      :item_id => id,
      :ordering => order,
      :attrs => JSON.generate(attrs)
    )
  }

  # Link the item to its unit, and that unit's ancestors.
  if doc.text_at("entityOnly")
    done = Set.new
    aorder = 1000
    doc.text_at("entityOnly").split("|").each_with_index { |unit, order|
      next unless ALL_UNITS.include? unit
      UnitItem.create(
        :unit_id => unit,
        :item_id => id,
        :ordering_of_units => order,
        :is_direct => true
      )
      UnitHier.filter(:unit_id => unit, :is_direct => false).map { |hier| hier.ancestor_unit }.each { |ancestor|
        if !done.include?(ancestor)
          UnitItem.create(
            :unit_id => ancestor,
            :item_id => id,
            :ordering_of_units => aorder,  # maybe should this column allow null?
            :is_direct => false
          )
          aorder += 1
          done << ancestor
        end
      }
    }
  end
end

###################################################################################################
def convertUnits
  # Let the user know what we're doing
  puts "Converting units."
  startTime = Time.now

  # Load allStruct and traverse it
  DB.transaction do
    allStructPath = "/apps/eschol/erep/xtf/style/textIndexer/mapping/allStruct.xml"
    open(allStructPath, "r") { |io|
      convertUnits(Nokogiri::XML(io, &:noblanks).root, {}, {})
    }
  end
end

###################################################################################################
def convertItems
  # Let the user know what we're doing
  puts "Converting items."

  # Fire up threads for doing the work in parallel
  Thread.abort_on_exception = true
  prefilterThread = Thread.new { prefilterAll }
  indexThread = Thread.new { indexAll }

  # Convert all the items that are indexable
  QUEUE_DB.fetch("SELECT itemId, time FROM indexStates WHERE indexName='erep' ORDER BY itemId").each do |row|
    erepTime = Time.at(row[:time].to_i).to_datetime
    shortArk = row[:itemId].sub(%r{^ark:/?13030/}, '')
    item = Item[shortArk]
    if !item || item.last_indexed.nil? || item.last_indexed < erepTime
      $prefilterQueue << shortArk
    end
  end

  $prefilterQueue << nil  # end-of-queue
  prefilterThread.join
  indexThread.join
end

###################################################################################################
# Main action begins here

startTime = Time.now

case ARGV[0]
  when "--units"
    convertUnits
  when "--items"
    convertItems
  else
    STDERR.puts "Usage: #{__FILE__} --units|--items"
    exit 1
end

puts "Elapsed: #{Time.now - startTime} sec."
puts "Done."