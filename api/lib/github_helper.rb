class GithubHelper

  def self.hook_url(token)
    "#{SiteConfig[:base_url]}hook/github?token=#{token}"
  end

  def self.hook_payload(token)
    {
      name: "web",
      active: true,
      events: ["commit_comment","create","delete","download","follow","fork","fork_apply","gist","gollum","issue_comment","issues","member","public","pull_request","pull_request_review_comment","push","status","team_add","watch"],
      config: {
        url: GithubHelper.hook_url(token),
        content_type: "json"
      }
    }
  end

end