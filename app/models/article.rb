class Article < ActiveRecord::Base
  has_many :revisions
  has_many :articles_courses, class_name: ArticlesCourses
  has_many :courses, -> { uniq }, through: :articles_courses

  ####################
  # Instance methods #
  ####################
  def url
    escaped_title = title.gsub(" ", "_")
    "https://en.wikipedia.org/wiki/#{escaped_title}"
  end

  def update(data={})
    if data.blank?
      # Implement method for single-article lookup
    end

    self.title = data["page_title"].gsub("_", " ")
    if(self.revisions.count > 0)
      self.views = self.revisions.order('date ASC').first.views || 0
    else
      self.views = 0
    end
    self.save
  end

  def update_views(all_time=false, views=nil)
    if(self.views_updated_at.nil?)
      self.views_updated_at = CourseList.start.to_date
    end

    if(self.views_updated_at < Date.today)
      since = all_time ? CourseList.start.to_date : self.views_updated_at + 1.day

      if all_time
        self.revisions.each do |r|
          r.views = 0
          r.save
        end
      end

      # Update views on all revisions and the article
      new_views = views.nil? ? Grok.get_views_since_date_for_article(self.title, since) : views
      last = since
      new_views.each do |date, view_count|
        self.revisions.where("date <= ?", date).find_each do |r|
          r.views = r.views.nil? ? view_count : r.views + view_count
          r.save
        end
        last = date.to_date > last ? date.to_date : last
      end
      if(self.revisions.order('date ASC').first.views - self.views > 0)
        puts "Added #{self.revisions.order('date ASC').first.views - self.views} new views for #{self.title}"
      end
      self.views_updated_at = last
    end

    if(self.revisions.count > 0)
      self.views = self.revisions.order('date ASC').first.views
    else
      self.views = 0
    end
    self.save
  end

  # Cache methods
  def character_sum
    if(!read_attribute(:character_sum))
      update_cache()
    end
    read_attribute(:character_sum)
  end

  def revision_count
    read_attribute(:revisions_count) || revisions.size
  end

  def update_cache
    # Do not consider revisions with negative byte changes
    self.character_sum = revisions.where('characters >= 0').sum(:characters)
    self.save
  end

  #################
  # Class methods #
  #################

  # This is no longer used by the application
  def self.update_all_articles
    articles = Utils.chunk_requests(User.all) { |block|
      Replica.get_articles_edited_this_term_by_users block
    }
    articles.each do |a|
      article = Article.find_or_create_by(id: a["page_id"])
      article.update a
    end
  end

  def self.update_all_views(all_time=false)
    require "./lib/course_list"
    require "./lib/grok"
    views = {}
    threads = Article.all.each_with_index.map do |a, i|
      Thread.new(i) do |i|
        views_updated_at = a.views_updated_at || CourseList.start.to_date
        if(views_updated_at < Date.today)
          since = all_time ? CourseList.start.to_date : views_updated_at + 1.day
          views[a.id] = Grok.get_views_since_date_for_article(a.title, since)
        end
      end
    end

    threads.each { |t| t.join }

    Article.all.each do |a|
      a.update_views(all_time, views[a.id])
    end
  end

  def self.update_new_views
    Article.where("views_updated_at IS NULL").each do |a|
      Rails.logger.info "Pulling views for newly added Article: #{a.title}"
      a.update_views
    end
  end

  def self.update_all_caches
    Article.all.each do |a|
      a.update_cache
    end
  end

  # Variable descriptons
  def self.character_def
    "The gross sum of characters added to and removed from each article by the course's students during the course term"
  end

  def self.view_def
    "The sum of all views to each article during the course term"
  end
end