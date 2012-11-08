
function now() {
  return parseInt( (new Date()).getTime() / 1000 );
}

function ProjectStatus(zen, redis) {
  var self = this;
  self.zen = zen;
  self.redis = redis;
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
};

ProjectStatus.prototype.ask_future = function(channel, username, nick) {
  var self = this;

  var questions = [
    "What are you going to do tomorrow?",
    "What's your plan for tomorrow?",
  ];

  self.zen.send_privmsg(channel, nick+": "+questions[Math.floor(Math.random()*questions.length)]);
};

ProjectStatus.prototype.ask_blocking = function(channel, username, nick) {
  var self = this;

  var questions = [
    "What are you stuck on? Or 'not stuck on anything' is fine too.",
    "What is blocking you? 'Not blocked' is fine too.",
    "Are you blocked on anything?",
  ];

  self.zen.send_privmsg(channel, nick+": "+questions[Math.floor(Math.random()*questions.length)]);
};

ProjectStatus.prototype.ask_hero = function(channel, username, nick) {
  var self = this;

  var questions = [
    "Who is your hero and what did they do?",
  ];

  self.zen.send_privmsg(nick, nick+": "+questions[Math.floor(Math.random()*questions.length)]);
};

ProjectStatus.prototype.spoke = function(channel, username, nick) {
  var self = this;

  // Add this nick to the list of people currently in the channel.
  // Redundant with the "join" event, but could catch error cases.
  self.redis.sadd(self.rkey(channel), username);

  // Store the time they last spoke.
  self.redis.hset(self.rkey(channel+"-"+username), "lastspoke", now(), function(){});
};

ProjectStatus.prototype.joined = function(channel, username, nick) {
  var self = this;

  // Add this nick to the list of people currently in the channel.
  self.redis.sadd(self.rkey(channel), username);

  // Store the time they joined the channel.
  self.redis.hset(self.rkey(channel+"-"+username), "joined", now(), function(){});
};

ProjectStatus.prototype.parted = function(channel, username, nick) {
  var self = this;

  // Remove this nick from the list of people currently in the channel.
  self.redis.srem(self.rkey(channel), username);

  // Store the time they parted the channel.
  self.redis.hset(self.rkey(channel+"-"+username), "parted", now(), function(){});
};

ProjectStatus.prototype.members = function(channel, callback) {
  var self = this;

  self.redis.smembers(self.rkey(channel), callback);
};

module.exports.ProjectStatus = ProjectStatus;
