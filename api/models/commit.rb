class Commit
  include DataMapper::Resource
  property :id, Serial

  belongs_to :repo
  belongs_to :user, :required => false
  
  property :user_name, String, :length => 100
  property :user_email, String, :length => 100

  property :type, String, :length => 100
  
  property :date, DateTime
  property :text, String, :length => 255
  property :link, String, :length => 255

  property :created_at, DateTime
  property :updated_at, DateTime

  def self.create_from_payload(group, type, payload)
    repo = Repo.first_or_create(:link => payload["repository"]["html_url"], :group => group)
    user = User.first(:account_id => group.account_id, :github_username => payload["sender"]["login"])
    now = Time.now
    username = payload["sender"]["login"]

    case type
    when "commit_comment"
      Commit.create({
        type: type,
        repo: repo,
        user: user,
        date: now,
        comment: payload["comment"]
      })
    when "create"
      Commit.create({
        type: type,
        repo: repo,
        user: user,
        date: now,
        text: "#{username} created #{payload["ref_type"]} #{payload["ref"]}"
      })
    when "delete"
      Commit.create({
        type: type,
        repo: repo,
        user: user,
        date: now,
        text: "#{username} deleted #{payload["ref_type"]} #{payload["ref"]}"
      })
    when "download"
      Commit.create({
        type: type,
        repo: repo,
        user: user,
        date: now,
        text: "#{username} created download #{payload["download"]["name"]}",
        link: payload["download"]["html_url"]
      })
    when "follow"
      Commit.create({
        type: type,
        repo: repo,
        user: user,
        date: now,
        text: "#{username} followed #{payload["target"]["login"]}"
      })
    when "fork"
      Commit.create({
        type: type,
        repo: repo,
        user: user,
        date: now,
        text: "#{username} forked #{payload["forkee"]["full_name"]}",
        link: payload["forkee"]["html_url"]
      })
    when "fork_apply"
      Commit.create({
        type: type,
        repo: repo,
        user: user,
        date: now,
        text: "#{username} applied fork #{payload["head"]}"
      })
    when "gist"
      description = ""
      if payload["gist"]["description"]
        description = ": #{payload["gist"]["description"]}"
      end
      Commit.create({
        type: type,
        repo: repo,
        user: user,
        date: now,
        text: "#{username} #{payload["action"]}d gist#{description}",
        link: payload["gist"]["url"]
      })
    when "gollum"
      events = []
      payload["pages"].each do |page|
        events << Commit.create({ 
          type: type,
          repo: repo,
          user: user,
          date: now,
          text: "#{username} #{page["action"]} \"#{page["page_name"]}\"",
          link: page["html_url"]
        })
      end
      events
    when "issue_comment"
      summary = Sanitize.clean(payload["comment"]["body"])[0..140]
      Commit.create({
        type: type,
        repo: repo,
        user: user,
        date: now,
        text: "#{username} #{payload["action"]} comment: #{summary}...",
        link: payload["comment"]["url"]
      })
    when "issues"
      Commit.create({
        type: type,
        repo: repo,
        user: user,
        date: now,
        text: "#{username} #{payload["action"]} issue ##{payload["issue"]["number"]}: #{payload["issue"]["title"]}",
        link: payload["issue"]["html_url"]
      })
    when "member"
      Commit.create({
        type: type,
        repo: repo,
        user: user,
        date: now,
        text: "#{username} was #{payload["action"]} to the repository"
      })
    when "public"
      Commit.create({
        type: type,
        repo: repo,
        user: user,
        date: now,
        text: "#{username} open sourced the repository!"
      })
    when "pull_request"
      Commit.create({
        type: type,
        repo: repo,
        user: user,
        date: now,
        text: "#{username} #{payload["action"]} pull request #{payload["number"]}",
        link: payload["pull_request"]["html_url"]
      })
    when "pull_request_review_comment"
      summary = Sanitize.clean(payload["comment"]["body"])[0..140]
      Commit.create({
        type: type,
        repo: repo,
        user: user,
        date: now,
        text: "#{username} commented #{summary}",
        link: payload["comment"]["url"]
      })
    when "push"
      events = []
      events << Commit.create({
        type: type,
        repo: repo,
        user: user,
        date: now,
        text: "#{username} pushed #{payload["size"]} commits"
      })
      payload["commits"].each do |commit|
        if commit["distinct"]
          events << Commit.create({
            type: "commit",
            repo: repo,
            user: user,
            date: now,
            text: commit["message"],
            link: commit["url"]
          })
        end
      end
      events
    when "team_add"
      text = "#{username} "
      if payload["user"] and payload["repo"]
        text += "added #{payload["user"]["login"]} and #{payload["repo"]["full_name"]}"
      elsif payload["user"]
        text += "added #{payload["user"]["login"]}"
      elsif payload["repo"]
        text += "added #{payload["repo"]["full_name"]}"
      end
      text += " to team #{payload["team"]["name"]}"
      Commit.create({
        type: type,
        repo: repo,
        user: user,
        date: now,
        text: text,
        link: payload["team"]["url"]
      })
    when "watch"
      Commit.create({
        type: type,
        repo: repo,
        user: user,
        date: now,
        text: "#{payload["sender"]["login"]} #{payload["action"]} #{payload["repository"]["full_name"]}",
        link: repo.link
      })
    end
  end

  # Return a string appropriate for sending to an IRC channel
  def irc_message
    prefix = repo.link.gsub(/^https?:\/\//, '')
    "[#{prefix}] #{text} #{link}"
  end

end
