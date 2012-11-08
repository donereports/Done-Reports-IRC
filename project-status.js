
function ProjectStatus(zen) {
  var self = this;
  self.zen = zen;
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

module.exports.ProjectStatus = ProjectStatus;
