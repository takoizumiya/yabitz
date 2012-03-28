#!/usr/bin/env ruby

type = ARGV.shift.to_sym
force = ARGV.shift
maint = ARGV.shift

require_relative '../lib/yabitz/misc/init'

print "RACK_ENV:#{ENV['RACK_ENV']}, ok? [y/N] "

input = gets
input.chomp!
if input != 'Y' and input != 'y'
  puts "ok, exit. usage: RACK_ENV=(development|production) ruby scripts/main_models.rb MODEL_NAME force maint"
  exit 0
end

Stratum.operator_model(Yabitz::Model::AuthInfo)
Stratum.current_operator(Yabitz::Model::AuthInfo.query(:name => 'batchmaker', :unique => true))

unless force == 'force' and maint == 'maint'
  puts "usage: RACK_ENV=(development|production) ruby scripts/main_models.rb MODEL_NAME force maint"
  exit 0
end

require_relative '../lib/yabitz/misc/checker'
systemchecker_result = Yabitz::Checker.systemcheck(type)

systemchecker_result[:missing_references].each do |obj1, field, obj2|
  if obj2.respond_to?(:hosts)
    obj2.hosts_by_id += [obj1.oid]
    obj2.save
  elsif obj1.respond_to?(:hosts)
    obj1.hosts_by_id = obj1.hosts_by_id.select{|oid| oid != obj2.oid}
    obj1.save
  end
end
