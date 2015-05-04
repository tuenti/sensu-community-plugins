#!/usr/bin/env ruby
#
# Change status mutator
# ===
#
# DESCRIPTION:
#   Changes event severity if specified by the check.
#
#   Check has to define the behaviour like this:
#
#   "change_status": {
#     "status": 1,
#     "always": true,
#     "begin": "00:00",
#     "end": "8:00"
#   }
#
#   Values are optional, if always is set to true, the severity is always changed
#   and all other rules are ignored.
#
#   Time strings are parsed by Time.parse() ruby function.
#
# OUTPUT:
#   mutated JSON event
#
# PLATFORM:
#   all
#
# DEPENDENCIES:
#
#   json and time Ruby gems
#
# Copyright 2015 Tuenti SRE Team <sre@tuenti.com>
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.

require 'json'
require 'time'

# parse event
event = JSON.parse(STDIN.read, symbolize_names: true)
@check = event[:check]
@config = @check[:change_status]

def change_status(event)
  event[:mutated] = true
  event[:check][:status] = @config[:status] unless @config[:status].nil?
end

if @check[:status] != 0 and not @config.nil?
  if @config[:always] == true
    change_status event
  elsif @config[:begin] and @config[:end]
    now = Time.now
    begin_time = Time.parse(@config[:begin])
    end_time = Time.parse(@config[:end])
    if end_time > begin_time
      change_status event if now > begin_time and now < end_time
    else
      change_status event if (
        (now >= Time.parse("00:00:00") and now < end_time) or
        (now <= Time.parse("23:59:59") and now > begin_time)
      )
    end
  end
end

# output modified event
puts event.to_json
