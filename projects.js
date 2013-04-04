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

config.group_index_for_channel = function(channel) {
  for(var i in this.groups) {
    var group = this.groups[i];
    if(group.channel.toLowerCase() == channel.toLowerCase()) {
      return i;
    }
  }
  return false;
}

config.group_for_channel = function(channel) {
  var index = config.group_index_for_channel(channel);
  if(index) {
    return this.groups[index];
  } else {
    return false;
  }
}

// Given a nick, find the corresponding username by checking aliases defined in the config file
config.username_from_nick = function(nick) {
  username = nick.replace(/away$/, '').replace(/^[-_]+/, '').replace(/[-_\|]+$/, '').replace(/\|m$/, '');

  var users = this.users();
  for(var i in users) {
    var user = users[i];

    if(user.username == username) {
      // console.log("'"+nick+"' matched username " + user.username);
      return username;
    }

    for(var j in user.nicks) {
      if(user.nicks[j] == username) {
        // console.log("'"+nick+"' matched nick " + username);
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
  if(m.match(/^!(done|todo|block|hero|undone|quote|addhook) .+/) || m.match(/^(done|todo|block|hero|undone|quote)! .+/)) {
    return true;
  } else {
    return false;
  }
}

var pendingNamesCallbacks = {};

// Kick off a "NAMES" command, which will cause an event on the `sub` object to be triggered
function get_users_in_channel(channel, callback) {
  pendingNamesCallbacks[channel] = callback;
  redis.publish('out', JSON.stringify({
    version: 1,
    type: 'raw',
    command: "NAMES "+channel
  }));
}

function add_hook(repo_url, channel, cmd_channel) {
  console.log("Adding hook for "+channel+" to "+repo_url);
  projects.add_github_hook(channel, repo_url, function(data){
    if(data.error) {
      zen.send_privmsg(cmd_channel, "There was an error saving the Github hook! " + data.error + ": " + data.error_description);
    } else if(data.repo) {
      if(data.added) {
        zen.send_privmsg(cmd_channel, "Successfully added the hook for "+repo_url+"!");
      } else {
        zen.send_privmsg(cmd_channel, "The hook already was set for "+repo_url);
      }
    } else {
      zen.send_privmsg(cmd_channel, "There was an unknown error saving the Github hook!");
    }
  });
}

function on_message_received(channel, message) {
  var msg = JSON.parse(message);

  if(msg.type == "names") {
    // Run any pending callbacks with the list of nicks
    if(typeof pendingNamesCallbacks[msg.data.channel] == 'function') {
      pendingNamesCallbacks[msg.data.channel](msg.data.nicks);
      pendingNamesCallbacks[msg.data.channel] = null;
    }
    return;
  }

  var sender = msg.data.sender;
  if(msg.version == 1 && msg.type == "privmsg") {

    var username = config.username_from_nick(msg.data.sender);
    console.log("Username: "+username+" ("+msg.data.sender+")");
    console.log(message);

    // Reject users that are not in the config file
    if(username == false) {
      if(is_explicit_command(msg.data.message)) {
        zen.send_privmsg(msg.data.channel, "Sorry, I couldn't find an account for "+msg.data.sender);
      }
      return;
    }

    if(typeof msg.data.channel == 'undefined' || msg.data.channel.substring(0,1) != "#") {
      // Catch PMs for !addhook commands
      if(msg.data.message.match(/^!addhook (.+)/)) {
        if(match=msg.data.message.match(/^!addhook (https?:\/\/github.com\/[^\/]+\/[^\/\.]+) (#[a-z]+)/)) {
          // Check if channel is one we know about in the config file
          var group = config.group_for_channel(match[2]);
          if(group == false) { 
            zen.send_privmsg(msg.data.channel, "Sorry, there is no group for channel "+match[2]);
          } else {
            add_hook(match[1], match[2], msg.data.channel);
          }
        } else {
          zen.send_privmsg(msg.data.channel, "Sorry, I didn't get that. Try '!addhook https://github.com/user/repo #channel'");
        }
      }

      if(msg.data.message == "!reload users") {
        console.log("Reloading users");
        load_users();
        return;
      }

      if(match=msg.data.message.match(/^!join (#.+)$/)) {
        console.log("Joining "+match[1]);
        redis.publish('out', JSON.stringify({
          version: 1,
          type: 'raw',
          command: 'JOIN '+match[1]
        }));
        return;
      }
      return;
    }

    var user = config.user(username);

    // The report is associated with the channel the message comes in on, not the user's home channel.
    var group;
    if(msg.data.channel) {
      group = config.group_for_channel(msg.data.channel);
    }

    if(group == false) {
      if(msg.data.message && is_explicit_command(msg.data.message)) {
        zen.send_privmsg(msg.data.channel, "Sorry, there is no group for channel "+msg.data.channel);
      }
      return;
    }

    if(msg.type == "privmsg") {
      projects.spoke(msg.data.channel, username, msg.data.sender);

      var done = {
        message: false,
        type: false
      };

      if(match=msg.data.message.match(/^!addhook (.+)/)) {
        console.log("Adding Github hook: ["+match[1]+"]");
        if(match[1].match(/^https?:\/\/github.com\/[^\/]+\/[^\/\.]+$/)) {
          add_hook(match[1], msg.data.channel, msg.data.channel);
        } else {
          zen.send_privmsg(msg.data.channel, "Wrong URL format, try something like https://github.com/username/repo");
        }
        return;
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

      } else if((match=msg.data.message.match(/^!quote (.+)/)) || (match=msg.data.message.match(/^quote! (.+)/))) {
        console.log(username + " quoted: " + match[1]);

        // Record their reply
        done.message = match[1];
        done.type = "quote";

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

            // Then set the lastasked time to 0 to avoid logging another response from them in the near future
            projects.set_lastasked("all", "past");
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

    }
  }
}


// Update everyone's timezone and location data periodically
/*
var user_locations = {};
var location_cron_job_func = function(){
  projects.fetch_user_locations(function(locations){
    user_locations = locations;
    console.log("Fetched new location data");
  });
};
new cron('*(CUT)/30 * * * *', location_cron_job_func, null, true, "America/Los_Angeles");
location_cron_job_func();
*/


// Set up cron tasks to periodically ask people questions
cron_func = function(){

  var currentTime = new time.Date();

  for(var g in config.groups) {
    (function(group){

      // Get the list of people in the channel right now
      get_users_in_channel(group.channel, function(members){
        console.log("Found "+Object.keys(members).length+" users in channel "+group.channel);

        for(var nick in members) {
          (function(nick){

            var username = config.username_from_nick(nick);

            if(username == false)
              return;

            if(nick.match(/\|away/))
              return;

            var user = config.user(username);

            // Only ask users in their home channel
            if(config.group_for_user(username).channel != group.channel) {
              return;
            }

            // Set the date relative to the timezone of the group
            currentTime.setTimezone(group.timezone);

            // Check if we should ask this person.
            // Based on 
            //  1) current time (morning vs evening)
            //  2) when we last asked them (don't ask more than once every 3 hours)
            //  3) when we last got a response from them (don't ask more than 4 hours after getting a reply)
            //  4) when they are at their computer (last time they spoke in IRC)

            // Only ask what you're working on during normal hours
            if(currentTime.getHours() >= 9 && currentTime.getHours() <= 18) {
              console.log("Checking nick " + nick + " ("+user.username+") group " + group.channel);

              projects.get_lastasked("past", user.username, function(err, lastasked){
                projects.get_lastreplied("past", user.username, function(err, lastreplied){
                  console.log("  "+group.channel+" Last asked " + user.username + " " + (now()-lastasked) + " seconds ago, last replied " 
                    + (now()-lastreplied) + " seconds ago");

                  if( lastreplied == null || (now() - lastreplied) > (60 * 60 * 2) ) {
                    if( lastasked == null || (now() - lastasked) > (60 * 60 * 3) ) {
                      if( lastasked == null && lastreplied == null ) {
                        // First time this user is in the system. Bail out some portion 
                        // of the time to stagger the first questions to everyone.
                        if( Math.random() < 0.3 ) {
                          console.log("  skipping 30% of the time");
                          return;
                        }
                      }

                      console.log("  asking " + nick + "(" + user.username + ") on " + group.channel + " now!");
                      projects.ask_past(group.channel, user.username, nick);
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

          })(nick);

        }

      });
    })(config.groups[g]);
  }

};

function load_users() {
  // For each group, load the user list from the API
  for(var i in config.groups) {
    (function(index){
      // load_users sets values in the config hash in memory
      projects.load_users(config.groups[index].channel, function(data){
        console.log("Loaded Users for "+config.groups[index].channel);
        console.log(config.groups[index]);
      });
    })(i);
  }
}

process.on('uncaughtException', function(err) {
  console.log("!!!!!!!!!!!!!!!")
  console.log(err);
});


load_users();

// Start the listeners and cron job now, loading the user list will take a second
// so there's a delay on the initial cron function run to let it load first.

sub.subscribe('in');
sub.on('message', on_message_received);

// Set a cron job to ask users what they are doing periodically
new cron('*/5 * * * *', cron_func, null, true, "America/Los_Angeles");
setTimeout(cron_func, 3000); // Set a delay so the API calls have time to finish first

// Reload the user list every half hour
new cron('5,35 * * * *', load_users, null, true, "America/Los_Angeles");

