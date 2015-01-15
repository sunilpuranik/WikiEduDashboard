class User < ActiveRecord::Base
  has_many :courses_users, class_name: CoursesUsers
  has_many :courses, -> { uniq }, through: :courses_users
  has_many :revisions
  has_many :articles, -> { uniq }, through: :revisions

  enum role: [ :student, :instructor, :online_volunteer, :campus_volunteer ]

  ####################
  # Instance methods #
  ####################
  def contribution_url
    "https://en.wikipedia.org/wiki/Special:Contributions/#{self.wiki_id}"
  end

  # Cache methods
  def view_sum
    read_attribute(:view_sum) || articles.map {|a| a.views}.inject(:+) || 0
  end

  def course_count
    read_attribute(:course_count) || courses.size
  end

  def revision_count(after_date=nil)
    if(after_date.nil?)
      read_attribute(:revisions_count) || revisions.size
    else
      revisions.after_date(after_date).size
    end
  end

  def article_count
    read_attribute(:article_count) || article.size
  end

  def update_cache
    # Do not consider revisions with negative byte changes
    self.character_sum = Revision.joins(:article).where(articles: {namespace: 0}).where(user_id: self.id).where('characters >= 0').sum(:characters) || 0
    self.view_sum = articles.map {|a| a.views || 0}.inject(:+) || 0
    self.revisions_count = revisions.size
    self.article_count = articles.size
    self.course_count = courses.size
    self.save
  end


  #################
  # Class methods #
  #################
  def self.update_trained_users
    trained_users = Utils.chunk_requests(User.all) { |block|
      Replica.get_users_completed_training block
    }
    trained_users.each do |u|
      # Should this be find_by only?
      user = User.find_or_create_by(wiki_id: u["rev_user_text"])
      user.trained = true
      user.save
    end
  end

  def self.update_all_caches
    User.all.each do |u|
      u.update_cache
    end
  end
end
