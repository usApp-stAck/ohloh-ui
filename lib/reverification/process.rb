module Reverification
  class Process
    extend Amazon
    class << self
      def amazon_stat_settings
        @amazon_stat_settings ||= {}
      end

      def set_amazon_stat_settings(bounce_rate, amount_of_email)
        @amazon_stat_settings = {}
        @amazon_stat_settings[:bounce_rate] = bounce_rate.to_f
        @amazon_stat_settings[:amount_of_email] = amount_of_email.to_f
      end

      def sent_last_24_hrs
        ses.quotas[:sent_last_24_hours].to_f
      end

      def statistics_of_last_24_hrs
        ses.statistics.find_all { |s| s[:sent].between?(Time.now.utc - 24.hours, Time.now.utc) }
      end

      def check_statistics_of_last_24_hrs
        stats = statistics_of_last_24_hrs
        handler_ns = Reverification::ExceptionHandlers

        if bounce_rate(stats) >= amazon_stat_settings[:bounce_rate]
          raise(handler_ns::BounceRateLimitError, 'Bounce Rate exceeded')
        end
        raise(handler_ns::ComplaintRateLimitError, 'Complaint Rate exceeded 0.1%') if complaint_rate(stats) >= 0.1
      end

      def bounce_rate(stats)
        no_of_bounces = stats.inject(0.0) { |a, e| a + e[:bounces] }
        sent_last_24_hrs.zero? ? 0.0 : (no_of_bounces / sent_last_24_hrs) * 100
      end

      def complaint_rate(stats)
        no_of_complaints = stats.inject(0.0) { |a, e| a + e[:complaints] }
        sent_last_24_hrs.zero? ? 0.0 : (no_of_complaints / sent_last_24_hrs) * 100
      end

      def send_email(template, account, phase)
        check_statistics_and_wait_to_avoid_exceeding_throttle_limit
        resp = ses.send_email(template)
        return update_tracker(account.reverification_tracker, phase, resp) if account.reverification_tracker

        account.create_reverification_tracker(message_id: resp[:message_id], sent_at: Time.now.utc)
      end

      def check_statistics_and_wait_to_avoid_exceeding_throttle_limit
        check_statistics_of_last_24_hrs if sent_last_24_hrs >= amazon_stat_settings[:amount_of_email]
        sleep(1)
      end

      def poll_success_queue
        success_queue.poll(initial_timeout: 1, idle_timeout: 1) do |msg|
          message_hash = msg.as_sns_message.body_message_as_h
          message_hash['delivery']['recipients'].each do |recipient|
            account = Account.find_by_email recipient
            next unless account.try(:reverification_tracker)
            account.reverification_tracker.delivered! if account.reverification_tracker.pending?
          end
        end
      end

      def poll_bounce_queue
        bounce_queue.poll(initial_timeout: 1, idle_timeout: 1) do |msg|
          decoded_msg = msg.as_sns_message.body_message_as_h
          decoded_msg['bounce']['bouncedRecipients'].each do |recipient|
            handle_bounce_notification(decoded_msg['bounce']['bounceType'], recipient['emailAddress'])
          end
        end
      end

      def poll_complaints_queue
        complaints_queue.poll(initial_timeout: 1, idle_timeout: 1) do |msg|
          decoded_msg = msg.as_sns_message.body_message_as_h
          decoded_msg['complaint']['complainedRecipients'].each do |recipient|
            rev_tracker = Account.find_by_email(recipient['emailAddress']).try(:reverification_tracker)
            next unless rev_tracker
            rev_tracker.complained!
            rev_tracker.update feedback: decoded_msg['complaint']['complaintFeedbackType']
          end
        end
      end

      def start_polling_queues
        poll_success_queue
        poll_bounce_queue
        poll_complaints_queue
      end

      def cleanup
        ReverificationTracker.remove_reverification_trackers_for_verified_accounts
        ReverificationTracker.delete_expired_accounts
        ReverificationTracker.disable_accounts
        ReverificationTracker.remove_orphans
      end

      def handle_bounce_notification(type, recipient)
        rev_tracker = Account.find_by_email(recipient).try(:reverification_tracker)
        return unless rev_tracker
        case type
        when 'Permanent' then ReverificationTracker.destroy_account(recipient)
        when 'Transient', 'Undetermined' then rev_tracker.soft_bounced!
        end
      end

      def update_tracker(rev_tracker, phase, response)
        if phase == rev_tracker.phase_value
          rev_tracker.increment! :attempts
        else
          rev_tracker.update attempts: 1
        end
        rev_tracker.update(message_id: response[:message_id], status: 0, phase: phase, sent_at: Time.now.utc)
      end
    end
  end
end