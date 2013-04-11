class Report
  include DataMapper::Resource
  property :id, Serial

  belongs_to :group

  has n, :entries

  property :date_started, DateTime
  property :date_reminder_sent, DateTime
  property :date_completed, DateTime

  property :date_due, DateTime
  property :date_reminder, DateTime

  property :created_at, DateTime

  def create_entry(params)
    return Entry.create :report => self, :user => params[:user], :date => Time.now, :type => params[:type], :message => params[:message]
  end

  # Returns the current open report for the given group.
  # If a report is open but past the deadline, the open report is returned.
  # This means we need to explicitly close reports before new ones are created.
  # If no report is currently open, creates a new one.
  def self.current_report(group)
    report = Report.first(:group_id => group.id, :date_completed => nil, :order => [:date_started.desc])
    if report.nil?
      # Set the due date and reminder date based on the group settings

      # Get the last report
      last = Report.first(:group_id => group.id, :date_completed.not => nil, :order => [:date_started.desc])

      puts "Creating a new report"

      zone = Timezone::Zone.new :zone => group.due_timezone

      now = Time.now # UTC
      puts "Now (UTC) #{now}"

      local = now.localtime(zone.utc_offset)
      puts "Now (Local) #{local}"
      puts "Group due time #{group.due_time}, interval: #{group.due_day}"

      if group.due_day == "every"

        # Create the due date in the local timezone
        due = Time.new(local.year, local.month, local.day, group.due_time.hour, group.due_time.minute, group.due_time.second, zone.utc_offset)

        # If due date is in the past, re-calculate with day++
        if due < now
          puts "Recalculating"
          due = Time.new(local.year, local.month, local.day+1, group.due_time.hour, group.due_time.minute, group.due_time.second, zone.utc_offset)
        end

        puts "Due: #{due} (#{due.utc})"

      else
        # For weekly reports, figure out the due date based on the day of the week specified here

        # Create the due date in the local timezone set to today
        due = Time.new(local.year, local.month, local.day, group.due_time.hour, group.due_time.minute, group.due_time.second, zone.utc_offset)

        # increment the day until the day of the week matches the desired day of the week
        unless ['monday','tuesday','wednesday','thursday','friday','saturday','sunday'].include? group.due_day
          raise "Invalid due_day: #{group.due_day}"
        end

        while due.strftime('%A').downcase != group.due_day
          due = Time.new(due.year, due.month, due.day+1, group.due_time.hour, group.due_time.minute, group.due_time.second)
        end

        puts "Due: #{due} (#{due.utc})"
      end

      if group.send_reminder > 0
        reminder = due - (group.send_reminder * 60 * 60)
      else
        reminder = nil
      end

      # Store dates in the database in UTC
      report = Report.create :group_id => group.id, :date_started => Time.now, :date_due => due.utc, :date_reminder => reminder
    end
    report
  end
end