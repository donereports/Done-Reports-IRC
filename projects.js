var net = require('net'); 
var dgram = require('dgram');
var api = require('zenircbot-api');
var projectStatus = require('./project-status.js');
var cron = require('cron').CronJob;
var time = require('time');

var bot_config = api.load_config('../bot.json');
var config = api.load_config('./projects/config.json');
var zen = new api.ZenIRCBot(bot_config.redis.host,
                            bot_config.redis.port,
                            bot_config.redis.db);
var sub = zen.get_redis_client();
var redis = zen.get_redis_client();

var projects = new projectStatus.ProjectStatus(zen, redis, config);

function now() {
  return parseInt( (new Date()).getTime() / 1000 );
}

sub.subscribe('in');
sub.on('message', function(channel, message) {
  var msg = JSON.parse(message);
  var sender = msg.data.sender;
  if(msg.version == 1) {

    // TODO: Normalize the nick (msg.data.sender) and map to a username
    var username = projects.username_from_nick(msg.data.sender);

    if(msg.type == "directed_privmsg") {
      console.log(msg);

      projects.spoke(msg.data.channel, username, msg.data.sender);

      var done = {
        message: false,
        type: false
      };

      if(match=msg.data.raw_message.match(/^!done (.+)/)) {
        console.log(username + " did something: " + match[1]);

        // Record their reply
        done.message = match[1];
        done.type = "past";

      } else if(match=msg.data.raw_message.match(/^!todo (.+)/)) {
        console.log(username + " will do: " + match[1]);

        // Record their reply
        done.message = match[1];
        done.type = "future";

      } else if(match=msg.data.raw_message.match(/^!block(?:ing)? (.+)/)) {
        console.log(username + " is blocked on: " + match[1]);

        // Record their reply
        done.message = match[1];
        done.type = "blocking";

      } else if(match=msg.data.raw_message.match(/^loqi: (.+)/i)) {
        console.log(username + " did something: " + match[1]);

        // Check if we recently asked them a question, and if so, record a reply
        projects.get_lastasked("all", username, function(lastasked){
          if(lastasked) {
            var threshold = 60 * 30;
            if(now() - lastasked.past > threshold) {
              // Record a reply to "last"
              done.message = match[1];
              done.type = "past";

            } else if(now() - lastasked.future > threshold) {
              // Record a reply to "future"
              done.message = match[1];
              done.type = "future";

            } else if(now() - lastasked.blocking > threshold) {
              // Record a reply to "blocking"
              done.message = match[1];
              done.type = "blocking";

            } else if(now() - lastasked.hero > threshold) {
              // Record a reply to "hero"
              done.message = match[1];
              done.type = "hero";

            }
          }
        });
      }

      if(done.message) {
        projects.set_lastreplied(done.type, username);

        // Send the message to the API
        console.log(done);
        projects.submit_report(username, done.type, done.message, function(response){
          console.log("Got a response!");
          console.log(response);
          if(response.entry) {
            projects.send_confirmation(msg.data.sender, msg.data.channel);
          } else {
            if(response.error == "user_not_found") {
              zen.send_privmsg(msg.data.channel, "Sorry, I couldn't find an account for " + response.error_username);
            } else {
              zen.send_privmsg(msg.data.channel, "Something went wrong trying to store your report!");
            }
          }
        });
      }

    }
    if(msg.type == "privmsg") {
      console.log(msg);

      projects.spoke(msg.data.channel, username, msg.data.sender);

      if(msg.data.message == "who is in the channel right now?") {
        projects.members(msg.data.channel, function(err, reply){
          zen.send_privmsg(msg.data.channel, JSON.stringify(reply));

        });
      }

    }
    if(msg.type == "privmsg_action") {
      console.log(msg);


    }
    if(msg.type == "join") {
      console.log(msg);

      projects.joined(msg.data.channel, username, msg.data.sender);
    }
    if(msg.type == "part") {
      console.log(msg);

      projects.parted(msg.data.channel, username, msg.data.sender);
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

  // Get the list of people in the channel right now
  projects.members(config.channel, function(err, members){

    for(var i in config.users) {
      (function(user){

        console.log("Checking " + user.username);

        // Set the date relative to the timezone of the user's last location.
        // Fall back to Los Angeles timezone if not known.
        var timezone = "America/Los_Angeles";

        if(user_locations[user.geoloqi_user_id] && user_locations[user.geoloqi_user_id].context && user_locations[user.geoloqi_user_id].context.timezone) {
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
        if(currentTime.getHours() >= 7 && currentTime.getHours() <= 17) {

          projects.get_lastasked("past", user.username, function(err, lastasked){
            projects.get_lastreplied("past", user.username, function(err, lastreplied){
              console.log("  Last asked " + user.username + " on " + lastasked);
              console.log("  Last got a reply from " + user.username + " on " + lastreplied);

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

                    console.log("  asking " + user.username + " now!");
                    projects.get_nick(config.channel, user.username, function(err, current_nick){
                      projects.ask_past(config.channel, user.username, (current_nick ? current_nick : user.username));
                    });

                  }

                }
              }
            });
          });

        }
        // Only ask what you've done in the afternoon
        if(currentTime.getHours() >= 13 && currentTime.getHours() <= 19) {



        }

      })(config.users[i]);

    }

  });

};

new cron('*/5 * * * *', cronFunc, null, true, "America/Los_Angeles");

cronFunc();


// TODO: Handle a web hook here so Github commits can be used to set last seen time for users too



// TODO: Handle a web hook here for Geoloqi triggers when anyone gets to the office



