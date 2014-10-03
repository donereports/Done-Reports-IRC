process.chdir(__dirname);

var net = require('net'); 
var dgram = require('dgram');
var api = require('zenircbot-api');
var projectStatus = require('./donereports-lib.js');
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
    // Also look for channel aliases
    if(group.aliases.indexOf(channel.toLowerCase()) != -1) {
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
  return channels;
}

config.allCommands = function() {
  var commands = [];
  for(var i in this.commands) {
    commands.push(this.commands[i].command);
    if(this.commands[i].aliases) {
      for(var j in this.commands[i].aliases) {
        commands.push(this.commands[i].aliases[j]);
      }
    }
  }
  return commands;
}

// Return a list of all command types (not including command aliases)
// The list of types is global to the bot, so it's global to the network it's connecting to.
config.allTypes = function() {
  var types = [];
  for(var i in this.commands) {
    types.push(this.commands[i].command);
  }
  return types;
}

config.typeForCommand = function(command) {
  for(var i in this.commands) {
    if(this.commands[i].command == command ||
      (this.commands[i].aliases && this.commands[i].aliases.indexOf(command) != -1)) {
      return this.commands[i].command;
    }
  }
  return null;
}


function now() {
  return parseInt( (new Date()).getTime() / 1000 );
}

function parse_command(input) {
  var commands = config.allCommands();
  var regexp = "^(?:!("+commands.join("|")+")|("+commands.join("|")+")!) (.+)";
  var match;
  if(match=input.match(new RegExp(regexp))) {
    var command = null;
    if(match[1]) { command = match[1] }
    if(match[2]) { command = match[2] }
    return {
      type: config.typeForCommand(command),
      command: command,
      text: match[3]
    }
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
        zen.send_privmsg(cmd_channel, "Successfully added "+repo_url+" to the channel");
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

    if(msg.data.message == "!commands") {
      zen.send_privmsg(msg.data.channel, JSON.stringify(config.allCommands()));
      return;
    }

    // Reject users that are not in the config file
    if(username == false) {
      if(parse_command(msg.data.message)) {
        zen.send_privmsg(msg.data.channel, "Sorry, I couldn't find an account for "+msg.data.sender);
      }
      return;
    }

    //////////////////////////////////////////////////////////////////////////
    // Private messages (channel is undefined or doesn't start with #)
    if(typeof msg.data.channel == 'undefined' || msg.data.channel.substring(0,1) != "#") {
      // Catch PMs for !addrepo commands
      if(msg.data.message.match(/^!addrepo (https:?\/\/github\.com\/.+)/)) {
        if(match=msg.data.message.match(/^!addrepo (https?:\/\/github\.com\/[^\/]+\/[^\/\.]+) (#[a-z]+)/)) {
          // Check if channel is one we know about in the config file
          var group = config.group_for_channel(match[2]);
          if(group == false) { 
            zen.send_privmsg(msg.data.channel, "Sorry, there is no group for channel "+match[2]);
          } else {
            add_hook(match[1], match[2], msg.data.channel);
          }
        } else {
          zen.send_privmsg(msg.data.channel, "Sorry, I didn't get that. Try '!addrepo https://github.com/user/repo #channel'");
        }
      }

      if(msg.data.message == "!reload config") {
        console.log("Reloading config file");
        reload_config();
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

      if(match=msg.data.message.match(/^!mydone (#.+)$/)) {
        console.log("Generating temporary token for channel: "+match[1]);
        projects.mydone(match[1], username, function(data){
          if(data.url) {
            zen.send_privmsg(msg.data.sender, "You can view your in-progress entries here: " + data.url + " (this link will work for 5 minutes)");
          } else if(data.error_description) {
            zen.send_privmsg(msg.data.sender, data.error_description);
          } else {
            zen.send_privmsg(msg.data.sender, "An unknown error occurred!")
          }
        });
        return;
      }

      return;
    }
    //////////////////////////////////////////////////////////////////////////


    var user = config.user(username);

    // The report is associated with the channel the message comes in on, not the user's home channel.
    var group;
    if(msg.data.channel) {
      group = config.group_for_channel(msg.data.channel);
    }

    if(group == false) {
      if(msg.data.message && parse_command(msg.data.message)) {
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

      if(match=msg.data.message.match(/^!addrepo (https:?\/\/github\.com\/.+)/)) {
        console.log("Adding Github hook: ["+match[1]+"]");
        if(match[1].match(/^https?:\/\/github.com\/[^\/]+\/[^\/\.]+$/)) {
          add_hook(match[1], msg.data.channel, msg.data.channel);
        } else {
          zen.send_privmsg(msg.data.channel, "Wrong URL format, try something like https://github.com/username/repo");
        }
        return;
      }

      if(msg.data.message == "!mydone") {
        console.log("Generating temporary token");
        projects.mydone(msg.data.channel, username, function(data){
          if(data.url) {
            zen.send_privmsg(msg.data.sender, "You can view your in-progress entries here: " + data.url + " (this link will work for 5 minutes)");
            zen.send_privmsg(msg.data.channel, msg.data.sender+": I sent you a private message with a link to view your entries!");
          } else if(data.error_description) {
            zen.send_privmsg(msg.data.channel, data.error_description);
          } else {
            zen.send_privmsg(msg.data.channel, "An unknown error occurred!")
          }
          console.log(data);
        });
        return;
      }

      var input;
      if(input = parse_command(msg.data.message)) {
        // Normal commands like !done did this thing
        console.log(input);
        done.type = input.type;
        done.message = input.text;

        projects.record_response(username, done.type, done.message, msg.data.sender, msg.data.channel);

      } else if(match=msg.data.message.match(/^loqi: (.+)/i)) {
        console.log(username + " replied: " + match[1]);

        (function(done, line){
          // Check if we recently asked them a question, and if so, record a reply
          projects.get_lastasked("all", username, function(lastasked){
            console.log("Last asked:");
            console.log(lastasked);

            if(lastasked) {
              var threshold = 60 * 30; // Only recognize messages directed at Loqi: if Loqi has asked in the last half hour

              for(var i in config.allTypes()) {
                var type = config.allTypes()[i];
                if(lastasked[type] && now() - parseInt(lastasked[type]) < threshold) {
                  done.message = line;
                  done.type = type;
                }
              }

              if(done.message && done.type) {
                // Check if they recently replied with the same type. Prevents loqi from logging extra messages.
                // If they have replied in the last half hour already, ignore this.
                (function(done){
                  projects.get_lastreplied(done.type, username, function(err, lastreplied){
                    console.log("  User last replied "+lastreplied)
                    if((lastreplied == null) || (now() - parseInt(lastreplied) >= threshold)) {
                      projects.record_response(username, done.type, done.message, msg.data.sender, msg.data.channel);
                    } else {
                      console.log("  Ignoring directed message because user already replied "+(now()-parseInt(lastreplied))+" seconds ago");
                    }
                  });
                })(done);
              }
            }
          });
        })(done, match[1]);

      } else if((match=msg.data.message.match(/!undone (.+)/)) || (match=msg.data.message.match(/undone! (.+)/))) {
        console.log(username + " undid something: " + match[1]);

        projects.remove_response(username, match[1], msg.data.sender, msg.data.channel);
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
  // Add a random delay so we don't get throttled by the IRC server for sending too many commands
  (function(group){
    setTimeout(function(){
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
            //  3) when we last got a response from them (don't ask more than 4 hours after getting any sort of reply)
            //  4) TODO: randomly stagger the prompts to avoid the "9am burst"

            // Only ask what you're working on during normal hours
            var askFrom, askTo;
            if(group.prompt) {
              askFrom = group.prompt.hr_from;
              askTo = group.prompt.hr_to;
            } else {
              askFrom = 9;
              askTo = 18;
            }

            if(currentTime.getHours() >= askFrom && currentTime.getHours() <= askTo) {
              console.log("Checking nick " + nick + " ("+user.username+") group " + group.channel);

              var askType = 'doing';
              if(group.prompt) {
                askType = group.prompt.type;
              }

              projects.get_lastasked(askType, user.username, function(err, lastasked){
                projects.get_lastreplied("any", user.username, function(err, lastreplied){
                  console.log("  "+group.channel+" Last asked " + user.username + " " + (now()-lastasked) + " seconds ago, last replied " 
                    + (now()-lastreplied) + " seconds ago");

                  var shouldAsk = false;

                  if( lastreplied == null || (now() - lastreplied) > (60 * 60 * 2) ) {
                    if( lastasked == null || (now() - lastasked) > (60 * 60 * 3) ) {

                      if( lastasked == null && lastreplied == null ) {
                        // First time this user is in the system. Bail out some portion 
                        // of the time to stagger the first questions to everyone.
                        if( Math.random() < 0.3 ) {
                          console.log("  skipping 30% of the time");
                          shouldAsk = false;
                        } else {
                          shouldAsk = true;
                        }
                      } else {
                        shouldAsk = true;
                      }

                      if(shouldAsk) {
                        console.log("  asking " + nick + "(" + user.username + ") on " + group.channel + " now!");
                        projects.ask(askType, group.channel, user.username, nick);
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

          })(nick);

        }

      });

    }, Math.round(4 + (Math.random() * 30)) * 1000); // Random delay
  })(config.groups[g]);
  }

};

function reload_config(callback) {
  projects.load_config(function(data){
    if(data && data.groups != null && data.commands != null) {
      console.log("Loaded Config. "+data.groups.length+" groups");

      if(typeof callback == "function") {
        callback();
      }

      // Join all the channels now
      for(var i in config.groups) {
        var channel = config.groups[i].channel;
        console.log(channel);
        redis.publish('out', JSON.stringify({
          version: 1,
          type: 'raw',
          command: 'JOIN '+channel
        }));
      }
    } else {
      console.log("Error loading config");
      console.log(data);      
    }
  });
}

process.on('uncaughtException', function(err) {
  console.log("!!!!!!!!!!!!!!!")
  console.log(err);
});


reload_config(function(){

  // Start the listeners and cron job now
  sub.subscribe('in');
  sub.on('message', on_message_received);

  // Set a cron job to ask users what they are doing periodically
  new cron('*/5 * * * *', cron_func, null, true, "America/Los_Angeles");

  // Run the cron function now
  setTimeout(cron_func, 5000);

  // Reload the config file regularly
  new cron('0,15,30,45 * * * *', reload_config, null, true, "America/Los_Angeles");

});

