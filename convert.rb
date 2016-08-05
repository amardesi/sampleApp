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

# Local modules
require_relative 'subprocess'

# Special args
$testMode = ARGV.delete('--test')

# Connect to the databases we'll use
QUEUE_DB = Sequel.connect(YAML.load_file("config/queueDb.yaml"))
DB = Sequel.connect(YAML.load_file("config/database.yaml"))

# Queues for thread coordination
$prefilterQueue = SizedQueue.new($testMode ? 1 : 100)
$indexQueue = SizedQueue.new($testMode ? 1 : 100)

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
def prefilterOne(itemID)
  shortArk = itemID.sub(%r{^ark:/?13030/}, '')
  $prefilterDirsFile or $prefilterDirsFile = open("prefilterDirs.txt", "w")
  $prefilterDirsFile.puts "13030/pairtree_root/#{shortArk.scan(/\w\w/).join('/')}/#{shortArk}"
  $prefilterDirsCount += 1
  limit = $testMode ? 1 : 50
  if $prefilterDirsCount >= limit
    prefilterFlush
  end
end

###################################################################################################
def prefilterFlush
  $prefilterDirsCount > 0 or return
  $prefilterDirsFile.close

  # Run the XTF textIndexer in "prefilterOnly" mode. That way the stylesheets can do all the
  # dirty work of normalizing the various data formats, and we can use the uniform results.
  puts "Running prefilter batch of #{$prefilterDirsCount} items."
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
        puts "Got data for #{shortArk}."
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

  # Get ready for more.
  $prefilterDirsCount = 0
  $prefilterDirsFile = nil
end

###################################################################################################
def prefilterAll
  Thread.current[:name] = "prefilter thread"
  $prefilterDirsCount = 0
  loop do
    itemID = $prefilterQueue.pop
    itemID or break
    prefilterOne(itemID)
  end
  prefilterFlush
  $indexQueue << [nil, nil] # end-of-work
end

###################################################################################################
def indexAll
  Thread.current[:name] = "index thread"
  loop do
    itemID, prefilteredData = $indexQueue.pop
    itemID or break
    puts "#{itemID}"
  end
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
# Main action begins here

# Check command-line format
if ARGV.length != 1
  STDERR.puts "Usage: #{__FILE__} path/to/allStruct.xml"
  exit 1
end

# Let the user know what we're doing
puts "Converting units."
startTime = Time.now

# Load allStruct and traverse it
if false
  DB.transaction do
    allStructPath = ARGV[0]
    allStructPath or raise("Must specify path to allStruct")
    open(allStructPath, "r") { |io|
      convertUnits(Nokogiri::XML(io, &:noblanks).root, {}, {})
    }
  end
end

# Convert all the items that are indexable
puts "Converting items."
# Fire up threads for doing the work in parallel
Thread.abort_on_exception = true
prefilterThread = Thread.new { prefilterAll }
indexThread = Thread.new { indexAll }

QUEUE_DB.fetch("SELECT itemId FROM indexStates WHERE indexName='erep' ORDER BY itemId").each do |row|
  $prefilterQueue << row[:itemId]
end

$prefilterQueue << nil  # end-of-queue
prefilterThread.join
indexThread.join

# All done.
puts "  Elapsed: #{Time.now - startTime} sec"