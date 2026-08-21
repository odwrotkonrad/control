##[>] 🤖🤖
module Automation
  # Regen plans one downstream regen: which pin moves, how the bump reads, what the MR says.
  module Regen
    PIN_GLOB = '*.tfvars'
    SEMVER = /(latest|v?\d+\.\d+\.\d+)/

    Plan = Struct.new(:repo, :producer, :tag, :prev, :content_only, :pin_files, :old, :shown_tag, :bump, keyword_init: true) do
      def scope
        content_only ? 'docs-gen' : producer.name
      end

      def branch
        content_only ? "docs-gen-#{producer.name}-#{shown_tag}" : "#{producer.name}-#{shown_tag}"
      end

      def title
        content_only ? "[automation] chore(docs-gen): render at #{producer.name} #{shown_tag}" : "[automation] chore(#{producer.name}): #{old} → #{shown_tag}"
      end

      def body
        content_only ? "Automated docs regen: rendered at #{producer.name} #{shown_tag}." : "Automated #{producer.name} regen: #{old} → #{shown_tag} (#{bump} bump)."
      end

      def auto_merge?
        bump != 'major'
      end

      def render_env
        producer.env_var ? { producer.env_var => tag } : {}
      end

      def stale_mr?(title)
        title.start_with?("[automation] chore(#{scope}): ") && !title.match?(/→ v\d+\.0\.0$/)
      end
    end

    Skip = Struct.new(:message)

    def self.pin_pattern(producer)
      /(#{Regexp.escape(producer.pin_key)}\s*=\s*")#{SEMVER}"/
    end

    def self.plan(repo:, producer:, tag:, files:, prev: nil)
      pattern = pin_pattern(producer)
      pin_files = files.select { |_, content| content.match?(pattern) }.keys
      if pin_files.empty?
        return Skip.new("#{repo}: no #{producer.name} pin file, nothing to regen") unless producer.env_var

        return Plan.new(repo: repo, producer: producer, tag: tag, prev: prev, content_only: true, pin_files: [],
                        old: prev || 'none', shown_tag: tag, bump: 'patch')
      end

      old = files.fetch(pin_files.first)[pattern, 2]
      return Skip.new("#{repo}: already pinned to #{shown(old, tag)}") if old.delete_prefix('v') == tag.delete_prefix('v')

      Plan.new(repo: repo, producer: producer, tag: tag, prev: prev, content_only: false, pin_files: pin_files,
               old: old, shown_tag: shown(old, tag), bump: bump(old, tag))
    end

    def self.shown(old, tag)
      return tag unless old.match?(/\A[v0-9]/)

      old.start_with?('v') ? "v#{tag.delete_prefix('v')}" : tag.delete_prefix('v')
    end

    def self.bump(old, tag)
      return 'major' unless old.match?(/\A[v0-9]/)

      old_parts, new_parts = [old, tag].map { |v| v.delete_prefix('v').split('.').map(&:to_i) }
      return 'major' if new_parts[0] != old_parts[0]
      return 'minor' if new_parts[1] != old_parts[1]

      'patch'
    end

    def self.rewrite_pin(content, producer, tag)
      content.gsub(pin_pattern(producer)) { "#{Regexp.last_match(1)}#{producer.pin_written(tag)}\"" }
    end
  end
end
##[<] 🤖🤖
