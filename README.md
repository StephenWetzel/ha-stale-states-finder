# ha-stale-states-finder
Detect and notify when Home Assistant sensors that regularly update sudden get stuck in the same state.

## Motivation
I have a number of battery powered zigbee sensors that I use with Home Assistant, and when the battery is getting low in them, they will sometimes simply get stuck with their last reported state.  Instead of reporting `Unavailable` they will just report the same state forever.  For example, a temperature sensor which sees small fluctuations constantly will just suddenly get frozen at 73°F for a month.  Eventually they do go `Unavailable`, but sometimes it will take a very long time to happen, and all the while I assume the sensor is working, when it is not.

## Requirements
You should be able to send email from the machine this will run on, using `sendmail`.  Honestly, setting this up might be the most difficult part of this.  A guide on how to set it up is outside the scope of this readme.  Sorry, I know that is annoying, but there are a lot of guides out there if you search for your setup.  Also, it's technically not required if you use the `--debug` option I mention below.

You'll have to host your Home Assistant database in Postgres.  The script assumes the database is named `homeassistant` and that it has local access to it.  It would probably be easy to adapt the script to other database engines, but I don't use those, so I can't test it.

## Setup
You should clone the repo somewhere on the same machine that runs Home Assistant, and then in the directory create a `.env` file with the following two variables:
```
FROM_EMAIL_ADDRESS = 'my_from_email_address@gmail.com'
TO_EMAIL_ADDRESS = 'my_to_email_address@gmail.com'
```
Replacing the email addresses with your emails.

## Usage
Once you have the `.env` file setup, you can just run the script and it will connect to the database, check for stale states, and send an email if any are found.  It will also print the results to stdout.  If you don't want to send an email, either because you don't have it set up, or because you are testing, you can set debug mode by running with the `--debug` argument to exit the script before the email is sent.  Setting debug mode will give some other messy output, but shouldn't affect the running of the script.

You can just run the script with a cronjob, however often you want it to run.  I run it twice a day.

## Example Output
(After modifying the max_allowed_ratio variable to 1 so that some stale entities would be found)
```
23:54:54 steve@server:[~/bin/ha_stale_states_finder]: ruby --debug /home/steve/bin/ha_stale_states_finder/ha_state_gaps_finder.rb
Searching for states between 2025-06-07 and 2025-07-07, current hour 23
Entity sensor.usw_lite_16_poe_state currently hasn't had an update in 10 days 07:37:27.433007, with the previous longest gap seen of 6 days 14:06:54.072068 (ratio 1.57) and 33 total updates seen.
Entity sensor.oven_oven_upper_current_temperature currently hasn't had an update in 4 days 05:15:03.549875, with the previous longest gap seen of 3 days 17:59:08.986505 (ratio 1.13) and 37 total updates seen.
Lowest state_id seen: 237995524
```

## Notes
### Text files
There are two text files which will be created the first time the you run the script.

`min_state_id_seen.txt` is just the id of the oldest `state_id` the script should consider.  This greatly speeds up the script if you have a large database.  You may want to set it manually for the first run if the script takes a very long time to run, but the script will set it if you don't, and will keep it up to date after that.  Note that if you increase the `num_days` variable in the script, then you will need to edit the id stored in that file, or else the script won't look back any further that the previous limit.

`ignored_entity_ids.txt` is a list of `entity_ids` that the script should ignore, one `entity_id` per line.  I found there are a number of entities which have very irregular update patterns and will trip the script up, but which aren't really a concern for getting stuck.  If you run the script and get false positives you can put those here.  The first few lines of my file are
```
media_player.firefox
remote.firefox
media_player.shield_4
```

### Variables with default values
The script has the following 4 variables set within it.  You can edit them as you see fit, although these values seem to work well for me.
```
num_days = 30 # How many days back to look at to establish a baseline for what is a normal gap
max_allowed_ratio = 4 # ratio between longest gap seen in the num_days period and current gap
min_required_count = 30 # only look at entities with at least this number of states reported in the period
min_gap_to_care_about = 5 * 60 # Time in seconds for the minimum gap we should notify about
```

### A warning
This script directly accesses the home assistant database, which is not supported or recommended by the Home Assistant project.  It only does some basic read only queries, but you use it at your own risk, with the understanding it could corrupt your database and cause you to lose all your data.  Also, if there are any schema changes to the database it could suddenly break this script.  I will likely update it when I notice this, but I don't always run the latest version of Home Assistant, so it might take me a while to notice.
