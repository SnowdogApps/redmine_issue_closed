Rails.configuration.to_prepare do
  require 'hooks/controller_issue_hook'
end

module IssueClosed
  class DelayedClose < Struct.new(:issue_id)
    def perform
      issue = Issue.find issue_id
      if issue.status.state == false
        # add journal
        bot_user = User.find_by_login(Setting.bot_login)
        issue.init_journal(bot_user) unless bot_user.nil?

        issue.status = IssueStatus.find_by_state true
        issue.save
      end
    end    
  end
      
  module IssueStatusesController
    def self.included base
      base.class_eval do
        
        # alias_method :_index, :index unless method_defined? :_index
        
        # def index
        #   _index
        #   render :template => 'issue_statuses/issue_closed_list' unless request.xhr?
        # end
        
        def update_issue_closed
          (statuses = IssueStatus.all).each do |status|
            case status.id
            when params[:closed].to_i
              status.state = true
            when params[:resolved].to_i
              status.state = false
            else
              status.state = nil
            end
            status.save!
          end
          redirect_to :action => :index
        end
      end
   end
  end
  
  module MixinIssue 
    def self.included base
      base.class_eval do
        after_destroy :destroy_issue
        
        private
        
        def destroy_issue
          Delayed::Job.destroy(delayed_job_id) if Delayed::Job.find_by_id(delayed_job_id) != nil
        end
      end
    end
  end

  module IssuesController 
    def self.included base
      base.class_eval do
        alias_method :_update, :update unless method_defined? :_edit
        
        def update
          status_before_update = @issue.status
          _update
          
          if not (@issue.project.enabled_modules.detect { |enabled_module| enabled_module.name == 'issue_closed' }) == nil and \
            status_before_update != @issue.status

            to_destroy_id = @issue.delayed_job_id
            delayed_job_id = nil
            
            if @issue.status.state == false
              job = Delayed::Job.enqueue DelayedClose.new(@issue.id), 0, 7.days.from_now
              delayed_job_id = job.id
            end

            @issue.delayed_job_id = delayed_job_id
            @issue.save :callbacks => false

            # in case of change closed to resolved dj could not exists
            dj = Delayed::Job.find_by_id(to_destroy_id) unless to_destroy_id == nil
            dj.destroy unless dj.nil?
            
          end
        end
      end
    end    
  end
end

ActionDispatch::Callbacks.to_prepare do
    begin
      require_dependency 'application'
    rescue LoadError
      require_dependency 'application_controller'
    end

  IssueStatusesController.send :include, IssueClosed::IssueStatusesController
  IssuesController.send :include, IssueClosed::IssuesController
  Issue.send :include, IssueClosed::MixinIssue
end
