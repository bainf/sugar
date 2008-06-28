require 'digest/sha1'
require 'md5'

class User < ActiveRecord::Base

    UNSAFE_ATTRIBUTES = :id, :username, :hashed_password, :admin, :activated, :banned, :last_active, :created_at, :updated_at, :posts_count, :discussions_count, :inviter_id

    # Virtual attributes for clear text passwords
	attr_accessor :password, :confirm_password
	attr_accessor :password_changed

    has_many :discussions, :foreign_key => 'poster_id'
    has_many :posts
    belongs_to :inviter, :class_name => 'User'
    has_many :invitees, :class_name => 'User', :foreign_key => 'inviter_id'

    validate do |user|
		# Has the password been changed?
		if user.password && !user.password.blank?
			if user.password == user.confirm_password
				new_hashed_password = User.hash_string( user.password )
				# Has the password changed?
				if new_hashed_password != user.hashed_password
					user.hashed_password = new_hashed_password
					user.password_changed = true
				end
			else
				user.errors.add( :password,         "must be confirmed" )
				user.errors.add( :confirm_password, "must be confirmed" )
			end
		end
	end
	
	validates_presence_of   :hashed_password, :username, :email
	validates_uniqueness_of :username
	validates_format_of     :username, :with => /^[\w\d\-\s_#!]+$/

    # Class methods
	class << self
	    
        # Finds users with activity within some_time. The last_active column is only 
        # updated every 10 minutes, smaller values won't work.
	    def find_online(some_time=15.minutes)
	        User.find(:all, :conditions => ['activated = 1 AND last_active > ?', some_time.ago], :order => 'username ASC')
        end
	    
		# Hash a string for password usage
		def hash_string( string )
			Digest::SHA1.hexdigest( string )
		end
		
        # Deletes attributes which normal users shouldn't be able to touch from a param hash
		def safe_attributes(params)
		    safe_params = params.dup
		    UNSAFE_ATTRIBUTES.each do |r|
		        safe_params.delete(r)
	        end
            return safe_params
	    end
	end
	
    def participated_count
        Post.count_by_sql("SELECT COUNT(DISTINCT discussion_id) FROM posts WHERE posts.user_id = #{self.id}")
    end

	def paginated_discussions(options)
	    discussions_count = self.participated_count

        limit = options[:limit] || 30
        num_pages = (discussions_count.to_f/limit).ceil
        page  = (options[:page] || 1).to_i
        page = 1 if page < 1
        page = num_pages if page > num_pages
        offset = limit * (page - 1)

        discussions = Discussion.find(
            :all,
            :joins      => "INNER JOIN posts ON discussions.id = posts.discussion_id",
            :group      => "discussions.id",
            :conditions => ['posts.user_id = ?', self.id],
            :limit      => limit, 
            :offset     => offset,
            :order      => 'sticky DESC, last_post_at DESC',
            :include    => [:poster, :last_poster, :category]
        )

        # Inject the pagination methods on the collection
        class << discussions; include Paginates; end
        discussions.setup_pagination(:total_count => discussions_count, :page => page, :per_page => limit)
        
        return discussions
    end
	
    # Is the password valid?
	def valid_password?(pass)
		(self.class.hash_string(pass) == self.hashed_password) ? true : false
	end
	
    # Is the user online?
	def online?
	    (self.last_active && self.last_active > 15.minutes.ago) ? true : false
    end
    
    # Generates a Gravatar URL
    def gravatar_url(options={})
        unless @gravatar_url
            options[:size] ||= 24
            gravatar_hash = MD5::md5(self.email)
            @gravatar_url = "http://www.gravatar.com/avatar/#{gravatar_hash}?s=#{options[:size]}&amp;r=x"
        end
        @gravatar_url
    end
	
end
