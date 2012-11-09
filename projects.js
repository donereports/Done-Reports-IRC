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
    var username = msg.data.sender;

    if(msg.type == "directed_privmsg") {
      console.log(msg);

      projects.spoke(msg.data.channel, username, msg.data.sender);

      if(done=msg.data.raw_message.match(/!done (.+)/)) {
        console.log(username + " did something: " + done[1]);
      } else {
        // Check if we recently asked them a question, and if so, record a reply


      }

    }
    if(msg.type == "privmsg") {
      console.log(msg);

      projects.spoke(msg.data.channel, username, msg.data.sender);

      if(msg.data.message == "who") {
        projects.members(msg.data.channel, function(err, reply){
          zen.send_privmsg(msg.data.channel, JSON.stringify(reply));

        });
      }

      if(msg.data.message == "ask_past") {
        console.log("ask_past");
        projects.ask_past(msg.data.channel, username, msg.data.sender);
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
            console.log("  Last asked " + user.username + " on " + lastasked);

            if( lastasked == null || (now() - lastasked) > (60 * 60 * 3) ) {

              projects.get_lastreplied("past", user.username, function(err, lastreplied){
                console.log("  Last got a reply from " + user.username + " on " + lastasked);

                if( lastreplied == null || (now() - lastreplied) > (60 * 60 * 4) ) {

                  if( members.indexOf(user.username) != -1 ) {
                    console.log("  " + user.username + " is online!");

                    if( lastasked == null && lastreplied == null ) {
                      // First time this user is in the system. Bail out 90% of the time
                      // to stagger the first questions to everyone.
                      if( Math.random() < 0.9 ) {
                        return;
                      }
                    }

                    console.log("  asking " + user.username + " now!");
                    projects.get_nick(config.channel, user.username, function(err, current_nick){
                      projects.ask_past(config.channel, user.username, (current_nick ? current_nick : user.username));

                    });

                  }

                }
              });

            }
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



