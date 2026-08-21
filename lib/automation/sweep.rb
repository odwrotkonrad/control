##[>] 🤖🤖
module Automation
  # Sweep lands open [automation] MRs that missed their auto-merge window: arms running ones, merges green ones.
  module Sweep
    RUNNING = %w[running pending created waiting_for_resource preparing scheduled].freeze

    Decision = Struct.new(:action, :message)

    def self.decide(mr)
      title = mr['title']
      return Decision.new(:ignore, nil) unless title.start_with?('[automation] ')
      return Decision.new(:skip, 'major bump, human review') if title.match?(/→ v\d+\.0\.0$/)
      return Decision.new(:ok, 'already armed') if mr['merge_when_pipeline_succeeds']

      status = mr.dig('head_pipeline', 'status') || 'none'
      return Decision.new(:merge, 'merge (pipeline green)') if status == 'success'
      return Decision.new(:arm, "arm auto-merge (pipeline #{status})") if RUNNING.include?(status)
      return Decision.new(:leave, "pipeline #{status}, needs a human") if %w[failed canceled].include?(status)

      Decision.new(:leave, "pipeline #{status}, merge status #{mr['detailed_merge_status'] || 'unknown'}")
    end

    def self.run(group:, dry_run:)
      mrs = Gitlab.api("groups/#{group}/merge_requests?state=opened&per_page=100")
      return puts('sweep: no open regen MRs') if mrs.empty?

      mrs.each do |listed|
        mr_api = "projects/#{listed['project_id']}/merge_requests/#{listed['iid']}"
        mr = Gitlab.api(mr_api)
        label = "#{mr['title']} (project #{listed['project_id']} !#{listed['iid']})"
        decision = decide(mr)
        case decision.action
        when :ignore then next
        when :skip then puts "skip  #{label}: #{decision.message}"
        when :ok then puts "ok    #{label}: #{decision.message}"
        when :leave then puts "leave #{label}: #{decision.message}"
        when :merge, :arm
          next puts("DRY   #{label}: would #{decision.message}") if dry_run

          act(mr_api, mr, decision.action, label)
        end
      end
    end

    def self.act(mr_api, mr, action, label)
      merge_status = mr['detailed_merge_status'] || 'unknown'
      form = { sha: mr['sha'], should_remove_source_branch: true }
      form[:merge_when_pipeline_succeeds] = true if action == :arm
      if Gitlab.put("#{mr_api}/merge", form)
        puts "#{action == :arm ? 'armed' : 'merged'} #{label}"
      else
        puts "leave #{label}: #{action == :arm ? 'auto-merge' : 'merge'} refused, merge status #{merge_status}"
      end
    end
  end
end
##[<] 🤖🤖
