module IssueClosed
  module Hooks
    class ControllerIssueHook < Redmine::Hook::ViewListener
      
      def controller_issues_bulk_edit_before_save(context={})
        @issue = context[:issue]

        if module_enable?
          to_destroy_id = @issue.delayed_job_id
          delayed_job_id = nil
          
          if @issue.status.state == false
            job = Delayed::Job.enqueue DelayedClose.new(@issue.id), 0, 7.days.from_now
            delayed_job_id = job.id
          end

          @issue.delayed_job_id = delayed_job_id

          # in case of change closed to resolved dj could not exists
          dj = Delayed::Job.find_by_id(to_destroy_id) unless to_destroy_id == nil
          dj.destroy unless dj.nil?
          
        end
        
      end
      
      def module_enable?
        not (@issue.project.enabled_modules.detect { |enabled_module| enabled_module.name == 'issue_closed' }) == nil
      end
      
    end
  end
end