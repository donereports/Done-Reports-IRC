IRC Project Status Updates
==========================

Collection
==========

The goal of this project is to collect information about what people are working with minimal psychological stress and overhead on everyone.

Everybody on the team is already on IRC all the time, and also has their email inbox open constantly. The most frictionless interface must be one of those two.

The problem with email is that people will start to treat it as a burden. We get tons of email in our inboxes all the time, and this should not be something that "needs attention" or "needs to be replied to". We want a quick and short reply to the prompts, and we don't want the prompt to get lost in an inbox of other email. 

IRC is a great mechanism to collect data since it is by nature more conversational than email. By using IRC, we can make a bot that appears to be asking questions like a regular person, and it should feel like having a short conversation rather than filling out a report.

The goal is to collect enough information from people to send daily updates to everyone. Since we are traveling a lot in the near future, we need a system to facilitate sharing progress updates quickly and easily while being geographically distributed.


Triggers
--------

The goal is to ask someone what they're doing while they're in the context of work or in a project. We don't want to disturb people while they're at home and not working.

Criteria we can use when deciding when to send a prompt:

* When someone last spoke
* When someone joined the channel
* When someone gets to the office (Geoloqi trigger)
* When someone commits code (Github post-commit hook)


Questions
---------

### Past
* What have you been working on?
* What are you doing?
* What are you working on?

### Future
* What are you going to do tomorrow?
* What's your plan for tomorrow?

### Blocking
* What are you stuck on?
* What is blocking you?
* Are you blocked on anything?

### Appreciation
* Who is your hero?

### Channel message vs private message?

The only question that should be asked privately is the "Who is your hero?" question. This way, the answer to this question is left as a surprise for the end-of-the-week in-person meetings.

The rest of the questions should be asked publicly, to facilitate more communication. By asking these questions publicly, everybody is kept more in the loop if they happen to see the question answered while on IRC, so there will be generally more transparency and information sharing. If someone sees someone else's "what is blocking you" answer, they may be able to help resolve the blocking issue sooner rather than later.


Unsolicited Reports
-------------------

People may wish to give unsolicited reports even if the bot does not prompt them, for example when they finish a task. The system should be able to accept unsoliited reports.

The syntax of this is not yet determined.

* `Loqi: I did this.` Has the potential of false positives, also cannot associate with a question.
* `!done I did this.` Is explicit but somewhat hard to remember.


Reply Format
------------

Replies should be addressed to the bot in this format:

```
Loqi: wrote the "Accounts" method on the API
```

If they don't respond in 30 minutes, ask the same question again with instructions.

```
aaronpk: What have you been working on? (reply like "Loqi: I did this stuff")
```

Frequency
---------

The big question is how often to ask these questions so as not to come off as annoying and pestering.





Friendly Responses
------------------

The bot should always reply in a friendly manner so people feel like they are talking with someone rather than filling out a report.

* Thanks!
* Got it!
* Cheers!
* Nice.

The responses should never be cheesy or patronizing. An example of an inappropriate response is "Great, keep it up!"


Delivery
========

After collecting peoples' responses, we need to publish a report with everyone's responses. The report should be posted to the private wiki, and a link delivered to IRC. This is to avoid the overhead of processing yet another email. 


When to Deliver?
----------------

* Send when 5/8 submit reports
* Reports will be sent no longer than 20 hours apart
* Reports will be sent between 9am-5pm Pacific time

When posting a report, sends a message to #geoloqi-team.

Anybody who was not in the channel at the time the report is posted will get the message the next time they join the channel as a private message.


API
===

The server knows the current report that is being collected.

`POST /api/report/new`

* auth
* username - The username sending the report
* type - past, future, blocking, hero, unknown
* message - The text of the report

Post a new report. 

`POST /api/report/compile`

Compile all pending reports into a record, and send the report out.


Data Model
==========


Accounts
--------

* id
* name


Groups
------

* id
* account_id
* token
* name
* email_recipient
* due_day - every, sunday, monday, tuesday, etc
* due_time - i.e. 5:00pm
* due_timezone - America/Los_Angeles


Reports
-------

* id
* group_id
* date_started
* date_completed


Items
-----

* id
* report_id
* user_id
* date
* type
* message


Users
-----

* account_id
* username
* email


User-Groups
-----------

* user_id
* group_id



