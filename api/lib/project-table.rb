
class ProjectTable

  def self.response(group, days=7)
    data = []

    query = repository(:default).adapter.select('SELECT COUNT(1) AS num, `repo_id`
      FROM `commits`
      JOIN `repos` ON `commits`.repo_id = `repos`.id
      WHERE `repos`.group_id = ?
        AND `date` > ?
      GROUP BY `repo_id`
      ORDER BY `num` DESC
      LIMIT 10', group.id, (DateTime.now - days))
    repos = Repo.all(:id => query.map{|q| q.repo_id})
    repos.each do |repo|
      query = repository(:default).adapter.select('SELECT COUNT(1) AS num, `user_id`
        FROM `commits`
        WHERE `repo_id` = ?
          AND `user_id` IS NOT NULL
          AND `date` > ?
        GROUP BY `user_id`
        ORDER BY num DESC
        LIMIT 10', repo.id, (DateTime.now - days))
      user_count = Hash[*query.map{|q| [q.user_id, q.num]}.flatten]
      users = User.all(:id => query.map{|q| q.user_id})

      row = {
        name: repo.name,
        users: []
      }

      users.each do |user|
        email = user.email # Fall back to the user's email address if no github email is set
        email = user.github_email if user.github_email

        row[:users] << {
          name: user.github_username,
          img: "http://www.gravatar.com/avatar/#{Digest::MD5.hexdigest(email.downcase)}?s=144&d=https://a248.e.akamai.net/assets.github.com%2Fimages%2Fgravatars%2Fgravatar-user-420.png",
          num: user_count[user.id]
        }
      end

      data << row
    end
    
    data
  end
end