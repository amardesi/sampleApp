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
require 'pp'
require 'sequel'
require 'time'
require 'yaml'

# Connect to the database into which we'll place data
DB = Sequel.connect(YAML.load_file("config/database.yaml"))

# Model classes for easy object-relational mapping in the database
class Unit < Sequel::Model
  unrestrict_primary_key
end

class UnitHier < Sequel::Model(:unit_hier)
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
DB.transaction do
  allStructPath = ARGV[0]
  allStructPath or raise("Must specify path to allStruct")
  open(allStructPath, "r") { |io|
    convertUnits(Nokogiri::XML(io, &:noblanks).root, {}, {})
  }
end

# All done.
puts "  Elapsed: #{Time.now - startTime} sec"