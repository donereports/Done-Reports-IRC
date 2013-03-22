process.chdir(__dirname);

var net = require('net'); 
var dgram = require('dgram');
var api = require('zenircbot-api');
var projectStatus = require('./project-status.js');
var cron = require('cron').CronJob;
var time = require('time');

var bot_config = api.load_config('../../bot.json');
var config = api.load_config('./config.json');
var zen = new api.ZenIRCBot(bot_config.redis.host,
                            bot_config.redis.port,
                            bot_config.redis.db);
var sub = zen.get_redis_client();
var redis = zen.get_redis_client();

var projects = new projectStatus.ProjectStatus(zen, redis, config);


// Set up some helper methods on the config object

// Return a list of all users across all groups with a new "group" key with their channel
config.users = function() {
  var users = [];
  for(var i in this.groups) {
    var group = this.groups[i];
    for(var j in group.users) {
      var user = group.users[j];
      user.channel = group.channel;
      user.timezone = group.timezone;
      users.push(user);
    }
  }

  return users;
}

// Return a specific user given their username
config.user = function(username) {
  var users = this.users();
  for(var i in users) {
    if(users[i].username == username) {
      return users[i];
    }
  }
}

config.group_for_user = function(username) {
  for(var i in this.groups) {
    var group = this.groups[i];
    for(var j in group.users) {
      var user = group.users[j];
      if(user.username == username) {
        return group;
      }
    }
  }
  return false;
}

config.group_for_channel = function(channel) {
  for(var i in this.groups) {
    var group = this.groups[i];
    if(group.channel.toLowerCase() == channel.toLowerCase()) {
      return group;
    }
  }
  return false;
}

// Given a nick, find the corresponding username by checking aliases defined in the config file
config.username_from_nick = function(nick) {
  username = nick.replace(/away$/, '').replace(/^[-_]+/, '').replace(/[-_]+$/, '').replace(/\|m$/, '');

  var users = this.users();
  for(var i in users) {
    var user = users[i];

    if(user.username == username) {
      console.log("'"+nick+"' matched username " + user.username);
      return username;
    }

    for(var j in user.nicks) {
      if(user.nicks[j] == username) {
        console.log("'"+nick+"' matched nick " + username);
        return user.username;
      }
    }
  }

  return false;
}

// Return all channels in the config file
config.channels = function() {
  channels = [];
  for(var i in this.groups) {
    channels.push(this.groups[i].channel);
  }
}


function now() {
  return parseInt( (new Date()).getTime() / 1000 );
}

function is_explicit_command(m) {
  if(m.match(/^!(done|todo|block|hero|undone) .+/) || m.match(/^(done|todo|block|hero|undone)! .+/)) {
    return true;
  } else {
    return false;
  }
}

sub.subscribe('in');
sub.on('message', function(channel, message) {
  console.log(message);
  var msg = JSON.parse(message);
  var sender = msg.data.sender;
  if(msg.version == 1) {

    var username = config.username_from_nick(msg.data.sender);
    console.log("Username: "+username+" ("+msg.data.sender+")");

    // Reject users that are not in the config file
    if(username == false) {
      if(is_explicit_command(msg.data.message)) {
        zen.send_privmsg(msg.data.channel, "Sorry, I couldn't find an account for "+msg.data.sender);
      }
      return;
    }

    if(msg.type == "quit") {
      // Quit messages don't include a channel
      projects.quit(username, msg.data.sender);
      return;
    }

    if(typeof msg.data.channel == 'undefined' || msg.data.channel.substring(0,1) != "#") {
      return;
    }

    var user = config.user(username);

    // The report is associated with the channel the message comes in on, not the user's home channel.
    // Except for "quit" messages which don't provide a channel
    var group;
    if(msg.data.channel) {
      group = config.group_for_channel(msg.data.channel);
    } else {
      group = config.group_for_user(username);
    }

    if(group == false) {
      if(msg.data.message && is_explicit_command(msg.data.message)) {
        zen.send_privmsg(msg.data.channel, "Sorry, there is no group for channel "+msg.data.channel);
      } else {
        console.log("No group for channel");
      }
      return;
    }

    if(username && msg.type == "join") {
      projects.joined(msg.data.channel, username, msg.data.sender);
    }
    if(username && msg.type == "part") {
      projects.parted(msg.data.channel, username, msg.data.sender);
    }

    if(msg.type == "privmsg") {

      console.log(msg);

      projects.spoke(msg.data.channel, username, msg.data.sender);

      var done = {
        message: false,
        type: false
      };

      if(msg.data.message == "!who") {
        projects.members(group.channel, function(err, members){
          console.log(members);
        });
      }

      if((match=msg.data.message.match(/^done! (.+)/)) || (match=msg.data.message.match(/^!done (.+)/))) {
        console.log(username + " did something: " + match[1]);

        done.message = match[1];
        done.type = "past";

      } else if((match=msg.data.message.match(/^todo! (.+)/)) || (match=msg.data.message.match(/^!todo (.+)/))) {
        console.log(username + " will do: " + match[1]);

        // Record their reply
        done.message = match[1];
        done.type = "future";

      } else if((match=msg.data.message.match(/^!block(?:ing|ed)? (.+)/)) || (match=msg.data.message.match(/^block(?:ing|ed)?! (.+)/))) {
        console.log(username + " is blocked on: " + match[1]);

        // Record their reply
        done.message = match[1];
        done.type = "blocking";

      } else if((match=msg.data.message.match(/^!hero (.+)/)) || (match=msg.data.message.match(/^hero! (.+)/))) {
        console.log(username + "'s hero: " + match[1]);

        // Record their reply
        done.message = match[1];
        done.type = "hero";

      } else if(match=msg.data.message.match(/^loqi: (.+)/i)) {
        console.log(username + " did something: " + match[1]);

        // Check if we recently asked them a question, and if so, record a reply
        projects.get_lastasked("all", username, function(lastasked){
          console.log("Last asked:");
          console.log(lastasked);

          if(lastasked) {
            var threshold = 60 * 30;

            if(lastasked.past && now() - parseInt(lastasked.past) < threshold) {
              // Record a reply to "last"
              done.message = match[1];
              done.type = "past";

            } else if(lastasked.future && now() - parseInt(lastasked.future) < threshold) {
              // Record a reply to "future"
              done.message = match[1];
              done.type = "future";

            } else if(lastasked.blocking && now() - parseInt(lastasked.blocking) < threshold) {
              // Record a reply to "blocking"
              done.message = match[1];
              done.type = "blocking";

            } else if(lastasked.hero && now() - parseInt(lastasked.hero) < threshold) {
              // Record a reply to "hero"
              done.message = match[1];
              done.type = "hero";

            } else {
              // done.message = match[1];
              // done.type = "unknown";

            }
          }

          if(done.message) {
            projects.record_response(username, done.type, done.message, msg.data.sender, msg.data.channel);
          }
        });
      } else if((match=msg.data.message.match(/!undone (.+)/)) || (match=msg.data.message.match(/undone! (.+)/))) {
        console.log(username + " undid something: " + match[1]);

        projects.remove_response(username, match[1], msg.data.sender, msg.data.channel);
      }

      if(done.message) {
        projects.record_response(username, done.type, done.message, msg.data.sender, msg.data.channel);
      }

    }

    if(msg.type == "privmsg_action") {
      console.log(msg);


    }
  }
});


// Update everyone's timezone and location data periodically
var user_locations = {};
var location_cron_job_func = function(){
  projects.fetch_user_locations(function(locations){
    user_locations = locations;
    console.log("Fetched new location data");
  });
};
new cron('*/30 * * * *', location_cron_job_func, null, true, "America/Los_Angeles");
location_cron_job_func();


// Set up cron tasks to periodically ask people questions
cronFunc = function(){

  var currentTime = new time.Date();

  for(var g in config.groups) {
    (function(group){

      // Get the list of people in the channel right now
      projects.members(group.channel, function(err, members){

        for(var i in group.users) {
          (function(user){

            console.log("Checking " + user.username);

            // Set the date relative to the timezone of the user's last location.
            // Fall back to Los Angeles timezone if not known.
            var timezone = group.timezone;

            if(user.geoloqi_user_id && user_locations[user.geoloqi_user_id] && user_locations[user.geoloqi_user_id].context && user_locations[user.geoloqi_user_id].context.timezone) {
              timezone = user_locations[user.geoloqi_user_id].context.timezone;
            }

            currentTime.setTimezone(timezone);

            // Check if we should ask this person.
            // Based on 
            //  1) current time (morning vs evening)
            //  2) when we last asked them (don't ask more than once every 3 hours)
            //  3) when we last got a response from them (don't ask more than 4 hours after getting a reply)
            //  4) when they are at their computer (last time they spoke in IRC)

            // Only ask what you're working on during normal hours
            if(currentTime.getHours() >= 9 && currentTime.getHours() <= 17) {

              projects.get_lastasked("past", user.username, function(err, lastasked){
                projects.get_lastreplied("past", user.username, function(err, lastreplied){
                  console.log("  Last asked " + user.username + " on " + lastasked);
                  console.log("  Last got a reply from " + user.username + " on " + lastreplied);
                  console.log(members);

                  if( lastreplied == null || (now() - lastreplied) > (60 * 60 * 2) ) {
                    if( lastasked == null || (now() - lastasked) > (60 * 60 * 3) ) {

                      if( members.indexOf(user.username) != -1 ) {
                        console.log("  " + user.username + " is online!");

                        if( lastasked == null && lastreplied == null ) {
                          // First time this user is in the system. Bail out some portion 
                          // of the time to stagger the first questions to everyone.
                          if( Math.random() < 0.4 ) {
                            return;
                          }
                        }

                        console.log("  asking " + user.username + " on " + group.channel + " now!");
                        projects.get_nick(group.channel, user.username, function(err, current_nick){
                          projects.ask_past(group.channel, user.username, (current_nick ? current_nick : user.username));
                        });

                      }

                    }
                  }
                });
              });

            }
            /*
            // Only ask what you've done in the afternoon
            if(currentTime.getHours() >= 13 && currentTime.getHours() <= 19) {



            }
            */

          })(group.users[i]);

        }

      });
    })(config.groups[g]);
  }

};

new cron('*/5 * * * *', cronFunc, null, true, "America/Los_Angeles");

cronFunc();



process.on('uncaughtException', function(err) {
  console.log("!!!!!!!!!!!!!!!")
  console.log(err);
});

