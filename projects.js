var net = require('net'); 
var dgram = require('dgram');
var api = require('zenircbot-api');
var projectStatus = require('./project-status.js');
var cron = require('cron');
var time = require('time');

var bot_config = api.load_config('../bot.json');
var zen = new api.ZenIRCBot(bot_config.redis.host,
                            bot_config.redis.port,
                            bot_config.redis.db);
var sub = zen.get_redis_client();
var redis = zen.get_redis_client();

var projects = new projectStatus.ProjectStatus(zen, redis);

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


// TODO: Handle a web hook here so Github commits can be used to set last seen time for users too



// TODO: Handle a web hook here for Geoloqi triggers when anyone gets to the office



