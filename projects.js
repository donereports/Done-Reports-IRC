var net = require('net'); 
var dgram = require('dgram');
var api = require('zenircbot-api');
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

sub.subscribe('in');
sub.on('message', function(channel, message) {
  var msg = JSON.parse(message);
  var sender = msg.data.sender;
  if(msg.version == 1) {
    if(msg.type == "directed_privmsg") {
      console.log(msg);


    }
    if(msg.type == "privmsg") {
      console.log(msg);

      if(msg.data.message == "who") {
        redis.smembers(rkey(msg.data.channel), function(err, reply){
          zen.send_privmsg(msg.data.channel, JSON.stringify(reply));

        });
      }

    }
    if(msg.type == "join") {
      console.log(msg);

      var ts = parseInt( (new Date()).getTime() / 1000 );

      // Add this nick to the list of people currently in the channel
      redis.sadd(rkey(msg.data.channel), msg.data.sender);

      // Store the time they joined the channel
      redis.hset(rkey(msg.data.channel+"-"+msg.data.sender), "joined", ts, function(){});

    }
    if(msg.type == "part") {
      console.log(msg);

      var ts = parseInt( (new Date()).getTime() / 1000 );

      // Remove this nick from the list of people currently in the channel
      redis.srem(rkey(msg.data.channel), msg.data.sender);

      // Store the time they parted the channel
      redis.hset(rkey(msg.data.channel+"-"+msg.data.sender), "parted", ts, function(){});

    }
  }
});
