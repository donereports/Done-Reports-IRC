var querystring = require('querystring');
var request = require('request');

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

ProjectStatus.prototype.ask = function(type, channel, username, nick) {
  var self = this;

  var questions = self.config.commands[type].questions;

  self.zen.send_privmsg(channel, nick+": "+questions[Math.floor(Math.random()*questions.length)]);
  self.set_lastasked(type, username);
};

ProjectStatus.prototype.send_confirmation = function(nick, channel, type) {
  var self = this;

  var replies = [];

  if(type == 'remove') {
    replies = [
      nick + ": ok it's gone",
      nick + ": erased!",
      nick + ": ok I removed it",
      nick + ": ok I got rid of it",
      nick + ": gone!"
    ];
  } else if(self.config.commands[type].responses) {
    for(var i in self.config.commands[type].responses) {
      replies.push(self.config.commands[type].responses[i].replace(/:nick/, nick));
    }
  } else {
    // Some default replies
    replies = [
      nick + ": Got it!",
      nick + ": Nice.",
      nick + ": nice",
      nick + ": Ok! Got it!",
      nick + ": ok!",
      nick + ": awesome!",
      nick + ": Awesome!"
    ];    
  }

  self.zen.send_privmsg(channel, replies[Math.floor(Math.random()*replies.length)]);
}


// Store the last time we asked each person each type of question

ProjectStatus.prototype.get_lastasked = function(type, username, callback) {
  var self = this;

  if(type == "all") {
    self.redis.mget([self.rkey("lastasked-done-"+username),self.rkey("lastasked-doing-"+username),self.rkey("lastasked-future-"+username),self.rkey("lastasked-blocking-"+username),self.rkey("lastasked-hero-"+username),self.rkey("lastasked-share-"+username)], function(err,data){
      if(data){
        callback({
          done: data[0],
          doing: data[1],
          future: data[2],
          blocking: data[3],
          hero: data[4],
          share: data[5]
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
  self.redis.set(self.rkey("lastreplied-any-"+username), now(), function(){});
}


// Tracks the current nick of each user based on the last time they spoke
ProjectStatus.prototype.spoke = function(channel, username, nick) {
  var self = this;

  // Store the user's current nick
  self.redis.hset(self.rkey(channel+"-"+username), "nick", nick, function(){});
}


ProjectStatus.prototype.get_nick = function(channel, username, callback) {
  var self = this;

  self.redis.hget(self.rkey(channel+"-"+username), "nick", callback);
}


ProjectStatus.prototype.record_response = function(username, type, message, nick, channel) {
  var self = this;

  console.log("Sending update...");

  self.set_lastreplied(type, username);

  // Send the message to the API
  self.submit_report(channel, username, type, message, function(response){
    console.log("Got a response!");
    // console.log(response);
    if(response.entry) {
      self.send_confirmation(nick, channel, type);
    } else {
      if(response.error == "user_not_found") {
        self.zen.send_privmsg(channel, "Sorry, I couldn't find an account for " + response.error_username);
      } else if(response.error == "user_not_in_group") {
        self.zen.send_privmsg(channel, "Sorry, you're not in this group!");
      } else if(response.error == "user_not_in_org") {
        self.zen.send_privmsg(channel, "Sorry, you're not in this organization!");
      } else {
        self.zen.send_privmsg(channel, "Something went wrong trying to store your entry!");
        console.log(response);
      }
    }
  });
}

ProjectStatus.prototype.remove_response = function(username, message, nick, channel) {
  var self = this;

  console.log("Removing...");

  // Send the message to the API
  self.submit_report(channel, username, 'remove', message, function(response){
    console.log("Got a response!");
    console.log(response);
    if(response.result == 'success') {
      self.send_confirmation(nick, channel, 'remove');
    } else {
      if(response.error == "user_not_found") {
        self.zen.send_privmsg(channel, "Sorry, I couldn't find an account for " + response.error_username);
      } else if(response.error == "entry_not_found") {
        self.zen.send_privmsg(channel, "Couldn't find that entry, make sure the text matches exactly");
      } else {
        self.zen.send_privmsg(channel, "Something went wrong trying to remove your entry!");
      }
    }
  });
}

ProjectStatus.prototype.submit_report = function(channel, username, type, message, callback) {
  var self = this;

  var group = self.config.group_for_channel(channel);
  if(group == false) {
    return false;
  }

  var user = self.config.user(username);

  try {
    request({
      url: self.config.api_url+'/api/report/'+(type == 'remove' ? 'remove' : 'new'),
      method: 'post',
      form: {
        token: group.token,
        username: username,
        type: type,
        message: message
      }
    }, function(error, response, body){
      if(error) {
        callback({
          error: 'unknown'
        });
      } else if(response.statusCode != 200) {
        callback({
          error: 'unknown',
          statusCode: response.statusCode
        });
      } else {
        try {
          callback(JSON.parse(body));
        } catch(e) {
          callback({
            error: 'parse_error'            
          });
        }
      }
    });
  } catch(e) {
    console.log('[api] EXCEPTION!');
    console.log(e);
    callback({
      error: 'exception',
      error_description: 'An unknown error occurred'
    });
  }
}

ProjectStatus.prototype.mydone = function(channel, username, callback) {
  var self = this;

  var group = self.config.group_for_channel(channel);
  if(group == false) {
    callback({
      error: 'no_group',
      error_description: 'Sorry, no group was found for the channel requested'
    })
    return false;
  }

  var user = self.config.user(username);

  try {
    request({
      url: self.config.api_url+'/api/report/mydone',
      method: 'post',
      form: {
        token: group.token,
        username: username
      }
    }, function(error, response, body){
      if(error) {
        callback({
          error: 'unknown',
          error_description: 'An unknown error occurred'
        });
      } else if(response.statusCode != 200) {
        callback({
          error: 'unknown',
          error_description: 'An unknown error occurred',
          statusCode: response.statusCode
        });
      } else {
        try {
          callback(JSON.parse(body));
        } catch(e) {
          callback({
            error: 'parse_error',
            error_description: 'An error occurred parsing the API response'
          });
        }
      }
    });
  } catch(e) {
    console.log('[api] EXCEPTION!');
    console.log(e);
    callback({
      error: 'exception',
      error_description: 'An unknown error occurred'
    });
  }
}

ProjectStatus.prototype.load_config = function(callback) {
  var self = this;

  try {
    request({
      url: self.config.api_url+'/api/bot/config',
      qs: {
        token: self.config.configtoken
      }
    }, function(error, response, body){
      if(error) {
        callback({
          error: 'unknown'
        });
      } else if(response.statusCode != 200) {
        callback({
          error: 'unknown',
          statusCode: response.statusCode
        });
      } else {
        try {
          var data = JSON.parse(body);
          if(data.groups && data.commands) {
            self.config.groups = data.groups;
            self.config.commands = data.commands;
            callback(data);
          } else {
            callback({
              error: 'bad_api_response'
            });
          }
        } catch(e) {
          callback({
            error: 'parse_error'            
          });
        }
      }
    });
  } catch(e) {
    console.log('[api] EXCEPTION!');
    console.log(e);
    callback({
      error: 'exception',
      error_description: 'An unknown error occurred'
    });
  }
};

ProjectStatus.prototype.add_github_hook = function(channel, repo_url, callback) {
  var self = this;

  var group = self.config.group_for_channel(channel);

  if(group == false) {
    return false;
  }

  try {
    request({
      url: self.config.api_url+'/api/github_hook/add',
      method: 'post',
      form: {
        token: group.token,
        repo_url: repo_url
      }
    }, function(error, response, body){
      if(error) {
        callback({
          error: 'unknown'
        });
      } else {
        try {
          var data = JSON.parse(body);
          if(data.error) {
            console.log("Error saving Github hook: " + data.error);
            callback(data);
          } else {
            callback(data);
          }
        } catch(e) {
          callback({
            error: 'parse_error'            
          });
        }
      }
    });
  } catch(e) {
    console.log('[api] EXCEPTION!');
    console.log(e);
    callback({
      error: 'exception',
      error_description: 'An unknown error occurred'
    });
  }
};

/*

ProjectStatus.prototype.fetch_user_locations = function(callback) {
  var self = this;

  var tokens = "";
  for(var i in self.config.users) {
    var user = self.config.users[i];
    if(user.token) {
      tokens += user.token + ",";
    }
  }

  if(tokens == "") {
    return;
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

*/

module.exports.ProjectStatus = ProjectStatus;
