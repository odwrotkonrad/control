##[>] 🤖🤖
require 'open3'
require 'json'

module Automation
  # Shell runs a command, returning its stdout, raising on failure unless told the failure is expected.
  module Shell
    ATTEMPTS = 10
    RETRY_DELAY = 10
    NETWORK_FAULT = /i\/o timeout|dial tcp|connection reset|unexpected EOF|early EOF|TLS handshake timeout|no such host|Could not resolve host|Connection timed out|unable to access|RPC failed|Operation timed out|Connection refused/i

    def self.capture(*cmd, chdir: nil)
      opts = chdir ? { chdir: chdir } : {}
      Open3.capture3(*cmd, **opts)
    end

    def self.run(*cmd, chdir: nil, allow_failure: false, quiet: false)
      out, err, status = capture(*cmd, chdir: chdir)
      warn err unless err.empty? || quiet
      return out if status.success?
      return nil if allow_failure

      raise "#{cmd.join(' ')} failed (#{status.exitstatus})"
    end

    def self.ok?(*cmd, chdir: nil)
      !run(*cmd, chdir: chdir, allow_failure: true, quiet: true).nil?
    end

    # Runs a command that talks to the network, retrying transport faults, failing fast on anything else.
    def self.run_network(*cmd, chdir: nil, allow_failure: false)
      ATTEMPTS.times do |i|
        out, err, status = capture(*cmd, chdir: chdir)
        return out if status.success?

        if err.match?(NETWORK_FAULT) && i < ATTEMPTS - 1
          warn "#{cmd.first(3).join(' ')}: network fault, retry #{i + 1}/#{ATTEMPTS - 1} in #{RETRY_DELAY}s"
          sleep RETRY_DELAY
          next
        end
        warn err unless allow_failure
        return nil if allow_failure

        raise "#{cmd.join(' ')} failed (#{status.exitstatus})"
      end
    end
  end

  # Gitlab calls the GitLab API through glab, the CI job's authenticated client.
  module Gitlab
    def self.api(path, method: 'GET', form: {}, allow_failure: false)
      cmd = ['glab', 'api', '-X', method, path] + form.flat_map { |k, v| ['-f', "#{k}=#{v}"] }
      out = Shell.run_network(*cmd, allow_failure: allow_failure)
      return nil if out.nil?

      out.empty? ? {} : JSON.parse(out)
    end

    def self.put(path, form, allow_failure: true)
      api(path, method: 'PUT', form: form, allow_failure: allow_failure)
    end
  end
end
##[<] 🤖🤖
