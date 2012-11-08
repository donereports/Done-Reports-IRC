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

// Returns a key namespaced to this project for use in Redis
function rkey(key) {
  return "projects-"+key;
}

function now() {
  return parseInt( (new Date()).getTime() / 1000 );
}

var projects = new projectStatus.ProjectStatus(zen);

sub.subscribe('in');
sub.on('message', function(channel, message) {
  var msg = JSON.parse(message);
  var sender = msg.data.sender;
  if(msg.version == 1) {

    // TODO: Normalize the nick (msg.data.sender) and map to a username
    var username = msg.data.sender;

    if(msg.type == "directed_privmsg") {
      console.log(msg);


    }
    if(msg.type == "privmsg") {
      console.log(msg);

      // Add this nick to the list of people currently in the channel.
      // Redundant with the "join" event below, but could catch error cases.
      redis.sadd(rkey(msg.data.channel), username);

      // Store the time they last spoke.
      redis.hset(rkey(msg.data.channel+"-"+username), "lastspoke", now(), function(){});

      if(msg.data.message == "who") {
        redis.smembers(rkey(msg.data.channel), function(err, reply){
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

      // Add this nick to the list of people currently in the channel.
      redis.sadd(rkey(msg.data.channel), username);

      // Store the time they joined the channel.
      redis.hset(rkey(msg.data.channel+"-"+username), "joined", now(), function(){});

    }
    if(msg.type == "part") {
      console.log(msg);

      // Remove this nick from the list of people currently in the channel.
      redis.srem(rkey(msg.data.channel), username);

      // Store the time they parted the channel.
      redis.hset(rkey(msg.data.channel+"-"+username), "parted", now(), function(){});

    }
  }
});


// TODO: Handle a web hook here so Github commits can be used to set last seen time for users too



// TODO: Handle a web hook here for Geoloqi triggers when anyone gets to the office



