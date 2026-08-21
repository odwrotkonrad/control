##[>] 🤖🤖🤖
require 'cgi'
require 'tmpdir'

module Automation
  # RegenRunner carries a Regen plan out: clone, move the pin, render, branch, MR, auto-merge.
  class RegenRunner
    RUNNING = %w[running pending created waiting_for_resource preparing scheduled].freeze

    def initialize(repo:, key:, tag:, prev: nil, workdir: nil, dry_run: false, group: 'konradodwrot')
      @repo = repo
      @key = key
      @tag = tag
      @prev = prev
      @workdir = workdir
      @dry_run = dry_run
      @group = group
      @project = CGI.escape("#{group}/#{repo}")
    end

    def run
      abort 'regen --dry-run needs --workdir <checkout> (no clone in dry-run)' if @dry_run && @workdir.nil?
      clone unless @workdir
      plan = Regen.plan(repo: @repo, key: @key, tag: @tag, prev: @prev, files: pin_files)
      return puts(plan.message) if plan.is_a?(Regen::Skip)
      return print_plan(plan) if @dry_run

      plan.render_env.each { |k, v| ENV[k] = v }
      close_stale_mrs(plan)
      plan.pin_files.each { |f| File.write(path(f), Regen.rewrite_pin(File.read(path(f)), plan)) }
      render
      git('checkout', '-b', plan.branch)
      git('add', '-A')
      return puts("#{@repo}: nothing rendered differently at #{plan.shown_tag}, no MR") if Shell.ok?('git', 'diff', '--cached', '--quiet', chdir: @workdir)

      commit(plan)
      push(plan)
      open_mr(plan)
      puts "#{@repo}: regen MR opened (#{plan.old} → #{plan.shown_tag}): #{plan.auto_merge? ? arm(plan) : 'major bump, awaiting human review'}"
    end

    private

    def path(file)
      File.join(@workdir, file)
    end

    def git(*args)
      Shell.run('git', *args, chdir: @workdir)
    end

    def clone
      @workdir = File.join(Dir.mktmpdir, File.basename(@repo))
      Shell.run_network('git', 'clone', '--depth', '1', "https://control-maintainer:#{ENV.fetch('CONTROL_GITLAB_TOKEN')}@gitlab.com/#{@group}/#{@repo}.git", @workdir)
    end

    def pin_files
      git('ls-files', '--', Regen::PIN_GLOB, "**/#{Regen::PIN_GLOB}").lines(chomp: true)
         .select { |f| File.file?(path(f)) }
         .to_h { |f| [f, File.read(path(f))] }
    end

    def print_plan(plan)
      puts <<~PLAN
        DRY RUN: regen plan for #{@repo}
          pin:        #{plan.old} → #{plan.shown_tag} (#{plan.bump} bump)
          render:     make render-templates in #{@workdir}
          supersede:  close open [automation] #{plan.scope} MRs (except major bumps)
          branch:     #{plan.branch}
          MR title:   #{plan.title}
          MR body:    #{plan.body}
          auto-merge: #{plan.auto_merge? ? 'yes' : 'no'} (set at creation, patch/minor only)
      PLAN
    end

    def close_stale_mrs(plan)
      Gitlab.api("projects/#{@project}/merge_requests?state=opened&per_page=100").each do |mr|
        next unless plan.stale_mr?(mr['title'])

        closed = Gitlab.put("projects/#{@project}/merge_requests/#{mr['iid']}", { state_event: 'close' })
        puts "#{@repo}: #{closed ? 'closed' : 'could not close'} superseded !#{mr['iid']} (#{mr['title']})"
      end
    end

    def render
      target = Shell.ok?('make', '-n', 'repo-render-templates', chdir: @workdir) ? 'repo-render-templates' : 'render-templates'
      puts "regen: rendering via make #{target}"
      Shell.run('make', target, chdir: @workdir)
    end

    def commit(plan)
      name = ENV.fetch('GITLAB_USER_NAME', 'control-maintainer')
      email = ENV.fetch('GITLAB_USER_EMAIL', 'control-maintainer@noreply.gitlab.com')
      git('-c', "user.name=#{name}", '-c', "user.email=#{email}", 'commit', '-m', plan.title)
    end

    def push(plan)
      if Shell.ok?('git', 'ls-remote', '--exit-code', '--heads', 'origin', plan.branch, chdir: @workdir)
        dropped = Gitlab.api("projects/#{@project}/repository/branches/#{CGI.escape(plan.branch)}", method: 'DELETE', allow_failure: true)
        puts "#{@repo}: #{dropped ? 'dropped' : 'could not drop'} stale branch #{plan.branch}, pushing over it"
      end
      Shell.run_network('git', 'push', '-u', '--force', 'origin', plan.branch, chdir: @workdir)
    end

    def open_mr(plan)
      form = { source_branch: plan.branch, target_branch: 'main', title: plan.title, description: plan.body, remove_source_branch: true }
      Gitlab.api("projects/#{@project}/merge_requests", method: 'POST', form: form, allow_failure: true) ||
        puts('regen: mr create reported failure, checking whether the MR exists')
    end

    def arm(plan)
      iid = Gitlab.api("projects/#{@project}/merge_requests?source_branch=#{plan.branch}&state=opened").dig(0, 'iid')
      abort "#{@repo}: no open MR for #{plan.branch}, create really did fail" unless iid

      mr_api = "projects/#{@project}/merge_requests/#{iid}"
      mr = Gitlab.api(mr_api)
      return 'auto-merge armed' if mr['merge_when_pipeline_succeeds']

      30.times do
        break if mr.dig('head_pipeline', 'id')

        sleep 2
        mr = Gitlab.api(mr_api)
      end
      status = mr.dig('head_pipeline', 'status') || 'none'
      return arm_pending(mr_api, mr, status) unless %w[success none].include?(status)

      if Gitlab.put("#{mr_api}/merge", { sha: mr['sha'], should_remove_source_branch: true })
        status == 'none' ? 'merged (repo runs no merge-request pipeline)' : 'merged (pipeline already green)'
      else
        "LEFT OPEN: merge refused, merge status #{mr['detailed_merge_status'] || 'unknown'}"
      end
    end

    def arm_pending(mr_api, mr, status)
      15.times do
        Gitlab.put("#{mr_api}/merge", { sha: mr['sha'], merge_when_pipeline_succeeds: true, should_remove_source_branch: true })
        mr = Gitlab.api(mr_api)
        break if mr['merge_when_pipeline_succeeds']

        if mr.dig('head_pipeline', 'status') == 'success'
          Gitlab.put("#{mr_api}/merge", { sha: mr['sha'], should_remove_source_branch: true })
          break
        end
        sleep 2
      end
      mr = Gitlab.api(mr_api)
      return "auto-merge armed (pipeline #{status})" if mr['merge_when_pipeline_succeeds']
      return 'merged (pipeline went green while arming)' if mr['state'] == 'merged'

      "LEFT OPEN: could not arm auto-merge, pipeline is #{mr.dig('head_pipeline', 'status') || 'none'}, merge status #{mr['detailed_merge_status'] || 'unknown'}"
    end
  end
end
##[<] 🤖🤖🤖
