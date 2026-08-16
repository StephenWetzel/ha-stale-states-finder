require 'sqlite3'

watchman_db_filename = File.expand_path("~/.homeassistant/.storage/watchman_v2.db")
watched_entity_ids_filename = 'watched_entity_ids.txt'

db = SQLite3::Database.new(watchman_db_filename, readonly: true)
db.execute 'PRAGMA query_only = ON'

watched_entity_ids = db.execute(<<~QUERY).flatten
  select distinct entity_id
  from found_items
  where item_type = 'entity'
  and entity_id is not null
  and entity_id != ''
  order by entity_id
QUERY

File.write(
  watched_entity_ids_filename,
  "#{watched_entity_ids.join("\n")}\n"
)

puts "Wrote #{watched_entity_ids.length} watched entity IDs to #{watched_entity_ids_filename}"
