class Report
  include DataMapper::Resource
  property :id, Serial

  belongs_to :group

  property :date_started, DateTime
  property :date_completed, DateTime

  property :created_at, DateTime

  # Returns the current open report for the given group.
  # If a report is open but past the deadline, the open report is returned.
  # This means we need to explicitly close reports before new ones are created.
  # If no report is currently open, creates a new one.
  def self.current_report(group)
    report = Report.first(:group_id => group.id, :date_completed => nil, :order => [:date_started.desc])
    if report.nil?
      report = Report.create :group_id => group.id, :date_started => Time.now
    end
    report
  end
end