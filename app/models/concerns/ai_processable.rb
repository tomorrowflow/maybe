module AiProcessable
  extend ActiveSupport::Concern

  PROGRESS_TTL = 5.minutes.to_i

  private
    def redis_key
      "family:#{family.id}:#{job_type}_progress"
    end

    def job_type
      raise NotImplementedError, "Subclass must define #job_type"
    end

    def init_progress(total)
      write_progress(
        status: "processing",
        processed: 0,
        total: total,
        rule_matched: 0,
        ai_processed: 0,
        started_at: Time.current.iso8601
      )
    end

    def update_progress(processed:, rule_matched: nil, ai_processed: nil)
      progress = read_progress
      return unless progress

      progress["processed"] = processed
      progress["rule_matched"] = rule_matched if rule_matched
      progress["ai_processed"] = ai_processed if ai_processed
      write_progress(progress)
    end

    def complete_progress
      progress = read_progress
      return unless progress

      progress["status"] = "complete"
      write_progress(progress)
    end

    def write_progress(data)
      data = data.transform_keys(&:to_s) if data.is_a?(Hash)
      Sidekiq.redis do |conn|
        conn.set(redis_key, data.to_json, ex: PROGRESS_TTL)
      end
      broadcast_progress(data)
    end

    def read_progress
      json = Sidekiq.redis { |conn| conn.get(redis_key) }
      json ? JSON.parse(json) : nil
    end

    def broadcast_progress(progress)
      Turbo::StreamsChannel.broadcast_replace_to(
        family,
        target: "#{job_type}_progress",
        partial: "shared/ai_progress",
        locals: { job_type: job_type, progress: progress }
      )
    end

    def self.progress_for(family, job_type)
      json = Sidekiq.redis { |conn| conn.get("family:#{family.id}:#{job_type}_progress") }
      json ? JSON.parse(json) : nil
    end
end
