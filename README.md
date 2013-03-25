IRC Project Status Updates
==========================

Collection
==========

The goal of this project is to collect information about what people are working with minimal psychological stress and overhead on everyone.

Everybody on the team is already on IRC all the time, and also has their email inbox open constantly. The most frictionless interface must be one of those two.

The problem with email is that people will start to treat it as a burden. We get tons of email in our inboxes all the time, and this should not be something that "needs attention" or "needs to be replied to". We want a quick and short reply to the prompts, and we don't want the prompt to get lost in an inbox of other email. 

IRC is a great mechanism to collect data since it is by nature more conversational than email. By using IRC, we can make a bot that appears to be asking questions like a regular person, and it should feel like having a short conversation rather than filling out a report.

The goal is to collect enough information from people to send daily updates to everyone. Since we are traveling a lot in the near future, we need a system to facilitate sharing progress updates quickly and easily while being geographically distributed.



IRC
===

### Commands

#### `!done A short sentence about the thing you did`

Use this command to send an update about what you did.

Alternate commands:

* `done! I did this`

#### `!todo I'm going to do this tomorrow`

Take quick notes on what you're going to do tomorrow. Everyone will see this in the email that goes out,
and you'll be reminded tomorrow when you read it.

Alternate commands:

* `todo! I'm going to do this tomorrow`

#### `!blocking I'm blocked on this thing`

If you're frustrated by something or something is preventing you from getting
things done, use the `!blocking` command to let people know! You never know, someone
may be able to help resolve whatever you're stuck on!

Alternate commands:

* `blocking!`
* `!block`
* `!blocked`
* `block!`
* `blocked!`

#### `!hero Loqi because he makes my life easier`

Use this to thank people for something they did!

Alternate commands:

* `hero! Loqi for being awesome`

#### `!addhook https://github.com/user/repo #channel`

Use this command to add the appropriate Github hook to a repo. You can send
this message as a PM to the IRC bot so you don't need to clutter the channel
with it if you're using it for a bunch of repos in a row. 

If you send this command in a channel, don't include the #channel on the end.


API
===

### `POST /api/report/new`

* token - The auth token for the group
* username - The username sending the report
* type - past, future, blocking, hero, unknown
* message - The text of the report

The server knows the current open report where responses are being collected.

Post a new entry to the current open report. (TODO: This should be renamed to /api/entry/new)


### `POST /api/report/remove`

* token - The auth token for the group
* username - The username sending the report
* message - The text of the report

Remove an entry. Only entries from an open report can be removed. Entries are matched on the entry
text, not by ID, so you must pass in the exact text of the entry to remove.


### `POST /api/user/new`

Bold fields are required. All others are optional.

* **token** - The auth token for the group
* **username** - A unique username for the user. If a user exists with this username already, the record is updated
* **email** - The email address of the user.
* nicks - A comma-separated string of alternate IRC nicks this user may be using.
* github_username - The user's Github username
* github_email - The user's email address in commits on Github


### `POST /hook/github`

* ?github_token=xxxxx - The internal Github auth token for the group
* ... whatever Github sends

This endpoint handles Github's event hooks. Note this is different from the standard git post-commit hooks. A full list of events sent by Github can be [found here](http://developer.github.com/v3/activity/events/types/).


### `POST /api/github_hook/add`

* token - The auth token for the group
* repo_url - The HTTP URL of the Github repositry

Add the appropriate Github hook to the specified repository. Will fail if the repo is not a Github URL.


### `GET /api/group/config`

* token - The auth token for the group

Returns a JSON config block for the group to be put into the IRC bot config file.



## License

Copyright 2013 Esri

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

A copy of the license is available in the repository's `LICENSE.txt` file.
