var https = require('https');

function now() {
  return parseInt( (new Date()).getTime() / 1000 );
}

function ProjectStatus(zen, redis, config) {
  var self = this;
  self.zen = zen;
  self.redis = redis;
  self.config = config;
}

// Returns a key namespaced to this project for use in Redis
ProjectStatus.prototype.rkey = function(key) {
  return "projects-"+key;
}

ProjectStatus.prototype.ask_past = function(channel, username, nick) {
  var self = this;

  var questions = [
    "What have you been working on in the last hour or so?",
    "What are you doing?",
    "What are you working on?",
  ];

  self.zen.send_privmsg(channel, nick+": "+questions[Math.floor(Math.random()*questions.length)]);
  self.set_lastasked("past", username);
};

ProjectStatus.prototype.ask_future = function(channel, username, nick) {
  var self = this;

  var questions = [
    "What are you going to do tomorrow?",
    "What's your plan for tomorrow?",
  ];

  self.zen.send_privmsg(channel, nick+": "+questions[Math.floor(Math.random()*questions.length)]);
  self.set_lastasked("future", username);
};

ProjectStatus.prototype.ask_blocking = function(channel, username, nick) {
  var self = this;

  var questions = [
    "What are you stuck on? Or 'not stuck on anything' is fine too.",
    "What is blocking you? 'Not blocked' is fine too.",
    "Are you blocked on anything?",
  ];

  self.zen.send_privmsg(channel, nick+": "+questions[Math.floor(Math.random()*questions.length)]);
  self.set_lastasked("blocking", username);
};

ProjectStatus.prototype.ask_hero = function(channel, username, nick) {
  var self = this;

  var questions = [
    "Who is your hero and what did they do?",
  ];

  self.zen.send_privmsg(nick, nick+": "+questions[Math.floor(Math.random()*questions.length)]);
  self.set_lastasked("hero", username);
};



// Store the last time we asked each person each type of question

ProjectStatus.prototype.get_lastasked = function(type, username, callback) {
  var self = this;

  if(type == "all") {
    self.redis.mget([self.rkey("lastasked-past-"+username),self.rkey("lastasked-future-"+username),self.rkey("lastasked-blocking-"+username),self.rkey("lastasked-hero-"+username)], function(err,data){
      if(data){
        callback({
          past: data[0],
          future: data[1],
          blocking: data[2],
          hero: data[3]
        });
      }
    });
  } else {
    self.redis.get(self.rkey("lastasked-"+type+"-"+username), callback);
  }
}

ProjectStatus.prototype.set_lastasked = function(type, username) {
  var self = this;

  self.redis.set(self.rkey("lastasked-"+type+"-"+username), now(), function(){});
}


// Store the last time we got a reply from each person

ProjectStatus.prototype.get_lastreplied = function(type, username, callback) {
  var self = this;

  self.redis.get(self.rkey("lastreplied-"+type+"-"+username), callback);
}

ProjectStatus.prototype.set_lastreplied = function(type, username) {
  var self = this;

  self.redis.set(self.rkey("lastreplied-"+type+"-"+username), now(), function(){});
}


// Store the last time we saw each person

ProjectStatus.prototype.get_lastseen = function(username, callback) {
  var self = this;

  self.redis.get(self.rkey("lastseen-"+username), callback);
};

ProjectStatus.prototype.set_lastseen = function(username, nick) {
  var self = this;

  // Store the time they were last seen. This is updated any time the user
  // says anything in any channel, joins any channel, or if any activity 
  // from external sources (like Github) is seen.
  self.redis.set(self.rkey("lastseen-"+username), now(), function(){});
};

ProjectStatus.prototype.spoke = function(channel, username, nick) {
  var self = this;

  // Add this nick to the list of people currently in the channel.
  // Redundant with the "join" event, but could catch error cases.
  self.redis.sadd(self.rkey(channel), username);

  // Store the time they last spoke in this channel.
  self.redis.hset(self.rkey(channel+"-"+username), "lastspoke", now(), function(){});

  // Store the user's current nick
  self.redis.hset(self.rkey(channel+"-"+username), "nick", nick, function(){});

  self.set_lastseen(username);
};

ProjectStatus.prototype.joined = function(channel, username, nick) {
  var self = this;

  // Add this nick to the list of people currently in the channel.
  self.redis.sadd(self.rkey(channel), username);

  // Store the time they joined the channel.
  self.redis.hset(self.rkey(channel+"-"+username), "joined", now(), function(){});

  // Store the user's current nick
  self.redis.hset(self.rkey(channel+"-"+username), "nick", nick, function(){});

  self.set_lastseen(username);
};

ProjectStatus.prototype.parted = function(channel, username, nick) {
  var self = this;

  // Remove this nick from the list of people currently in the channel.
  self.redis.srem(self.rkey(channel), username);

  // Store the time they parted the channel.
  self.redis.hset(self.rkey(channel+"-"+username), "parted", now(), function(){});

  // Store the user's current nick
  self.redis.hset(self.rkey(channel+"-"+username), "nick", nick, function(){});
};



ProjectStatus.prototype.members = function(channel, callback) {
  var self = this;

  self.redis.smembers(self.rkey(channel), callback);
};

ProjectStatus.prototype.get_nick = function(channel, username, callback) {
  var self = this;

  self.redis.hget(self.rkey(channel+"-"+username), "nick", callback);
}



ProjectStatus.prototype.fetch_user_locations = function(callback) {
  var self = this;

  var tokens = "";
  for(var i in self.config.users) {
    var user = self.config.users[i];
    tokens += user.token + ",";
  }

  self.geoloqi_request("GET", "/1/share/last?geoloqi_token=" + tokens, function(data){
    var response = {};
    if(data.locations) {
      for(var j in data.locations) {
        var loc = data.locations[j];
        response[loc.user_id] = loc;
      }
      callback(response);
    }
  });
}

ProjectStatus.prototype.geoloqi_request = function(method, path, callback) {
  var req = https.request({
    host: 'api.geoloqi.com',
    port: 443,
    path: path,
    method: method,
    headers: {
      'Host': 'api.geoloqi.com'
    }
  }, function(channelRes) {
    channelRes.setEncoding('utf8');
    
    if(channelRes.statusCode != 200) {
      console.log('[api] ' + channelRes.statusCode);
      response = '';
      channelRes.on('data', function (chunk) {
        response += chunk;
      });
      channelRes.on('end', function(){
        console.log('[api] ERROR: ' + response);
      });
    } else {
      response = '';
      channelRes.on('data', function (chunk) {
        response += chunk;
      });
      channelRes.on('end', function(){
        callback(JSON.parse(response));          
      });
    }
  }).end();
}


module.exports.ProjectStatus = ProjectStatus;
