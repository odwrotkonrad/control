##[>] 🤖🤖
require 'yaml'
require 'net/http'
require 'cgi'

module Automation
  # Aggregate merges every repo's cross-repo-interface declaration over the seeds into deps/deps-graph.yml.
  module Aggregate
    IFACE_PATH = '.repo/cross-repo-interface.yml'
    API = 'https://gitlab.com/api/v4'

    def self.combine(seeds, declared)
      seeds.merge(declared)
    end

    def self.inconsistencies(repos)
      produced = repos.flat_map { |repo, r| (r['downstream'] || []).map { |a| "#{repo}/#{a['name']}" } }
      consumed = repos.flat_map { |repo, r| (r['upstream'] || []).map { |up| [repo, up] } }
      missing = []
      repos.each do |repo, r|
        (r['edges'] || {}).each do |up, artifacts|
          artifacts.each do |a|
            consumed << [repo, up]
            missing << "#{repo} edge into #{a}, which #{repo} does not produce" unless produced.include?("#{repo}/#{a}")
          end
        end
      end
      consumed.each do |repo, up|
        missing << "#{repo} consumes #{up}, which no repo produces" unless produced.include?(up)
      end
      missing.uniq
    end

    def self.edges(repos)
      repos.sort.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(repo, r), downs|
        (r['upstream'] || []).each { |up| downs[up] << repo }
        (r['edges'] || {}).each { |up, artifacts| artifacts.each { |a| downs[up] << "#{repo}/#{a}" } }
      end.sort.to_h { |up, d| [up, d.uniq.sort] }
    end

    def self.render(repos)
      lines = ['##[>] 🤖', 'repositories:']
      repos.sort.each do |repo, r|
        lines << "  - repo: #{repo}"
        artifacts = r['downstream'] || []
        if artifacts.empty?
          lines << '    artifacts: []'
        else
          lines << '    artifacts:'
          artifacts.each { |a| lines << "      - {#{a.map { |k, v| "#{k}: #{v}" }.join(', ')}}" }
        end
      end
      lines << 'edges:'
      edges(repos).each do |up, downs|
        lines << "  #{up}:"
        downs.each { |d| lines << "    - #{d}" }
      end
      lines << '##[<] 🤖'
      lines.join("\n") + "\n"
    end

    def self.declared_local(workspace)
      Dir.glob(File.join(workspace, '**', IFACE_PATH)).map { |f| f.delete_prefix("#{workspace}/").delete_suffix("/#{IFACE_PATH}") }
    end

    def self.get(url, job_token: true)
      req = Net::HTTP::Get.new(URI(url))
      control = ENV['CONTROL_GITLAB_TOKEN'].to_s
      job = ENV['CI_JOB_TOKEN'].to_s
      if !control.empty?
        req['PRIVATE-TOKEN'] = control
      elsif job_token && !job.empty?
        req['JOB-TOKEN'] = job
      end
      Net::HTTP.start(req.uri.host, req.uri.port, use_ssl: true) { |http| http.request(req) }
    end

    def self.declared_remote(group)
      res = get("#{API}/groups/#{group}/projects?include_subgroups=true&per_page=100", job_token: false)
      raise "group listing failed: #{res.code}" unless res.is_a?(Net::HTTPSuccess)

      JSON.parse(res.body).map { |p| p['path_with_namespace'].delete_prefix("#{group}/") }
    end

    def self.fetch_remote(group, repo)
      project = CGI.escape("#{group}/#{repo}")
      res = get("#{API}/projects/#{project}/repository/files/#{CGI.escape(IFACE_PATH)}/raw?ref=main")
      res.is_a?(Net::HTTPSuccess) ? res.body.force_encoding("UTF-8") : nil
    end

    def self.run(seed_file:, graph_file:, out:, check:, group:, local: nil, own: nil)
      seeds = YAML.safe_load(File.read(seed_file, encoding: "UTF-8")).fetch('repos')
      candidates = (seeds.keys + (local ? declared_local(local) : declared_remote(group))).uniq.sort
      declared = candidates.to_h do |repo|
        body = local ? (File.read(File.join(local, repo, IFACE_PATH), encoding: "UTF-8") if File.file?(File.join(local, repo, IFACE_PATH))) : fetch_remote(group, repo)
        [repo, body]
      end.compact.transform_values { |body| YAML.safe_load(body) }.reject { |_, v| v.nil? }
      declared[own[:repo]] = YAML.safe_load(File.read(own[:path], encoding: 'UTF-8')) if own && File.file?(own[:path])
      repos = combine(seeds, declared)

      missing = inconsistencies(repos)
      abort(["inconsistent interfaces:", *missing].join("\n")) unless missing.empty?

      graph = render(repos)
      summary = "declared: #{declared.empty? ? 'none' : declared.keys.join(' ')}, seeded: #{candidates.size - declared.size} repos"
      if check
        current = File.read(graph_file, encoding: "UTF-8")
        if current != graph
          warn diff(current, graph)
          abort 'deps/deps-graph.yml drifted, rerun bin/automation aggregate (diff above)'
        end
        puts "deps-graph in sync (#{summary})"
      else
        File.write(out, graph)
        puts "wrote #{out} (#{summary})"
      end
    end

    def self.diff(current, generated)
      old_lines = current.lines(chomp: true)
      new_lines = generated.lines(chomp: true)
      first = (0...[old_lines.size, new_lines.size].max).find { |i| old_lines[i] != new_lines[i] }
      last_old = old_lines.size - 1
      last_new = new_lines.size - 1
      last_old -= 1 and last_new -= 1 while last_old > first && last_new > first && old_lines[last_old] == new_lines[last_new]
      ["--- deps/deps-graph.yml", "+++ generated", "@@ line #{first + 1} @@",
       *old_lines[first..last_old].map { |l| "- #{l}" },
       *new_lines[first..last_new].map { |l| "+ #{l}" }].join("\n")
    end
  end
end
##[<] 🤖🤖
