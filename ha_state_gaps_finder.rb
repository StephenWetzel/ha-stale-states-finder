require 'pg'
require 'fileutils'
require 'dotenv'

num_days = 30 # How many days back to look at to establish a baseline for what is a normal gap
max_allowed_ratio = 4 # ratio between longest gap seen in the num_days period and current gap
min_required_count = 30 # only look at entities with at least this number of states reported in the period
min_gap_to_care_about = 5 * 60 # Time in seconds for the minimum gap we should notify about
min_state_id_seen_filename = 'min_state_id_seen.txt'
ignored_entity_ids_filename = 'ignored_entity_ids.txt'
ignored_states = %w[unavailable unknown] # TODO: Implement this
Dotenv.load
Dotenv.require_keys('FROM_EMAIL_ADDRESS', 'TO_EMAIL_ADDRESS')

FileUtils.touch min_state_id_seen_filename
FileUtils.touch ignored_entity_ids_filename
min_state_id = File.read(min_state_id_seen_filename).to_i
ignored_entity_ids = File.readlines(ignored_entity_ids_filename).map(&:chomp)

conn = PG.connect(dbname: 'homeassistant')
date_result = conn.exec "select current_date, (current_date - interval '#{num_days} days')::date as oldest_date, date_part('hour', current_timestamp) as current_hour"
current_date = date_result.first['current_date']
oldest_date = date_result.first['oldest_date']
current_hour = date_result.first['current_hour'].to_i

puts "Searching for states between #{oldest_date} and #{current_date}, current hour #{current_hour}"
stale_states_query = <<~QUERY
  select 
    sm.entity_id,
    max(to_timestamp(states.last_updated_ts) - to_timestamp(old_states.last_updated_ts)) as longest_update_duration,
    now() - to_timestamp(max(states.last_updated_ts)) as current_update_duration,
    round(extract(epoch from (now() - to_timestamp(max(states.last_updated_ts)))) / extract(epoch from (max(to_timestamp(states.last_updated_ts) - to_timestamp(old_states.last_updated_ts)))), 2) as ratio,
    to_timestamp(max(states.last_updated_ts)) as last_update_dt,
    extract(epoch from (now() - to_timestamp(max(states.last_updated_ts)))) as current_update_duration_seconds,
    count(*),
    min(states.state_id) as min_state_id
  from states
  join states_meta sm using (metadata_id)
  join states old_states on old_states.state_id = states.old_state_id
  where states.state_id >= #{min_state_id}
  and to_timestamp(states.last_updated_ts) > current_date - interval '#{num_days} days'
  group by sm.entity_id
  order by 4 desc
QUERY
stale_states = conn.exec stale_states_query

min_state_id_seen = Float::INFINITY
problem_entity_count = 0
message_body = ''
stale_states.each do |row|
  entity_id = row['entity_id']
  count = row['count'].to_i
  min_state_id_seen = row['min_state_id'].to_i if row['min_state_id'].to_i < min_state_id_seen && row['min_state_id'].to_i > 0
  next if ignored_entity_ids.include? entity_id
  next unless row['ratio'].to_f > max_allowed_ratio && count > min_required_count && row['current_update_duration_seconds'].to_f > min_gap_to_care_about
  message = "Entity #{entity_id} currently hasn't had an update in #{row['current_update_duration']}, with the previous longest gap seen of #{row['longest_update_duration']} (ratio #{row['ratio']}) and #{count} total updates seen."
  puts message
  message_body += message
  message_body += "\n"
  problem_entity_count += 1
end

puts "Lowest state_id seen: #{min_state_id_seen}"
File.write(min_state_id_seen_filename, min_state_id_seen)

exit unless problem_entity_count > 0
exit if $DEBUG

from = ENV['FROM_EMAIL_ADDRESS']
to = ENV['TO_EMAIL_ADDRESS']
if problem_entity_count == 1
  subject = "Home Assistant: There is #{problem_entity_count} entity that has stopped updating"
else
  subject = "Home Assistant: There are #{problem_entity_count} entities that have stopped updating"
end

# TODO: Switch to email that supports bold around entities
email_message = <<~EMAIL_MESSAGE
  To: #{to}
  From: #{from}
  Subject: #{subject}
  #{message_body}
EMAIL_MESSAGE

IO.popen('/usr/sbin/sendmail -t', 'w') do |sendmail|
  sendmail.write(email_message)
end
