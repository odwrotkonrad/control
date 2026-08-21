##[>] 🤖🤖
require 'open3'
require 'json'

module Automation
  # Shell runs a command, returning its stdout, raising on failure unless told the failure is expected.
  module Shell
    def self.run(*cmd, chdir: nil, allow_failure: false, quiet: false)
      opts = chdir ? { chdir: chdir } : {}
      out, err, status = Open3.capture3(*cmd, **opts)
      warn err unless err.empty? || quiet
      return out if status.success?
      return nil if allow_failure

      raise "#{cmd.join(' ')} failed (#{status.exitstatus})"
    end

    def self.ok?(*cmd, chdir: nil)
      !run(*cmd, chdir: chdir, allow_failure: true, quiet: true).nil?
    end
  end

  # Gitlab calls the GitLab API through glab, the CI job's authenticated client.
  module Gitlab
    GET_ATTEMPTS = 5
    RETRY_DELAY = 3

    def self.api(path, method: 'GET', form: {}, allow_failure: false)
      cmd = ['glab', 'api', '-X', method, path] + form.flat_map { |k, v| ['-f', "#{k}=#{v}"] }
      attempts = method == 'GET' ? GET_ATTEMPTS : 1
      out = nil
      attempts.times do |i|
        last = i == attempts - 1
        out = Shell.run(*cmd, allow_failure: allow_failure || !last, quiet: allow_failure || !last)
        break unless out.nil?

        sleep RETRY_DELAY unless last
      end
      return nil if out.nil?

      out.empty? ? {} : JSON.parse(out)
    end

    def self.put(path, form, allow_failure: true)
      api(path, method: 'PUT', form: form, allow_failure: allow_failure)
    end
  end
end
##[<] 🤖🤖
