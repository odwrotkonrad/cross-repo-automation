##[>] 🤖🤖
require_relative 'pin'

module Automation
  # Regen plans one downstream regen: which pin moves, how the bump reads, what the MR says.
  module Regen
    #[why] two pin shapes, one per file kind: iac tracks refs as tfvars assignments, every other repo
    #   as its .repo/upstream.env lockfile. A consumer with neither has nothing to pin, which is what
    #   left every regen contentless before the lockfile existed
    PIN_GLOBS = ['*.tfvars', 'upstream.env'].freeze
    ENV_PIN_FILE = '.repo/upstream.env'
    SEMVER = /(latest|v?\d+\.\d+\.\d+)/

    Plan = Struct.new(:repo, :key, :tag, :prev, :content_only, :record_only, :pin_files, :old, :shown_tag, :bump, keyword_init: true) do
      def label
        Pin.label_of(key)
      end

      def scope
        return 'record' if record_only

        content_only ? 'docs-gen' : label
      end

      def branch
        return "record-#{label}-#{shown_tag}" if record_only

        content_only ? "docs-gen-#{label}-#{shown_tag}" : "#{label}-#{shown_tag}"
      end

      def title
        return "[automation] chore(record): #{label} #{old} → #{shown_tag}" if record_only

        content_only ? "[automation] chore(docs-gen): render at #{label} #{shown_tag}" : "[automation] chore(#{label}): #{old} → #{shown_tag}"
      end

      def body
        return "Records #{label} at #{shown_tag}. Nothing here is built from it, so no build and no release." if record_only

        content_only ? "Automated docs regen: rendered at #{label} #{shown_tag}." : "Automated #{label} regen: #{old} → #{shown_tag} (#{bump} bump)."
      end

      def auto_merge?
        bump != 'major'
      end

      def comment_body(reviewer)
        merge_note = auto_merge? ? 'Auto-merge armed.' : 'Auto-merge withheld, awaiting review.'
        "@#{reviewer} #{body} #{merge_note}"
      end

      def render_env
        { key => tag }
      end

      def pin_written
        old.match?(/\A\d/) ? tag.delete_prefix('v') : tag
      end

      def stale_mr?(title)
        title.start_with?("[automation] chore(#{scope}): ") && !title.match?(/→ v\d+\.0\.0$/)
      end
    end

    Skip = Struct.new(:message)

    def self.pin_pattern(key, file = nil)
      return /^(#{Regexp.escape(key)}=)#{SEMVER}$/ if env_pin_file?(file)

      /(#{Regexp.escape(key)}\s*=\s*")#{SEMVER}"/
    end

    def self.env_pin_file?(file)
      file.to_s.end_with?(ENV_PIN_FILE)
    end

    def self.plan(repo:, key:, tag:, files:, prev: nil, record_only: false)
      pin_files = files.select { |file, content| content.match?(pin_pattern(key, file)) }.keys
      if pin_files.empty?
        return Plan.new(repo: repo, key: key, tag: tag, prev: prev, content_only: true, record_only: record_only,
                        pin_files: [], old: prev || 'none', shown_tag: tag, bump: 'patch')
      end

      old = files.fetch(pin_files.first)[pin_pattern(key, pin_files.first), 2]
      return Skip.new("#{repo}: already pinned to #{shown(old, tag)}") if old.delete_prefix('v') == tag.delete_prefix('v')

      Plan.new(repo: repo, key: key, tag: tag, prev: prev, content_only: false, record_only: record_only,
               pin_files: pin_files, old: old, shown_tag: shown(old, tag), bump: bump(old, tag))
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

    def self.rewrite_pin(content, plan, file = nil)
      quote = env_pin_file?(file) ? '' : '"'
      content.gsub(pin_pattern(plan.key, file)) { "#{Regexp.last_match(1)}#{plan.pin_written}#{quote}" }
    end

    def self.substantive_diff?(diff)
      diff.to_s.split(/^@@[^\n]*\n/).drop(1).any? { |hunk| substantive_hunk?(hunk) }
    end

    def self.substantive_hunk?(hunk)
      lines = hunk.lines(chomp: true)
      deleted = lines.select { |l| l.start_with?('-') && !l.start_with?('---') }
      added = lines.select { |l| l.start_with?('+') && !l.start_with?('+++') }
      return true if deleted.size != added.size

      deleted.zip(added).any? { |was, now| strip_versions(was[1..]) != strip_versions(now[1..]) }
    end

    def self.strip_versions(line)
      line.gsub(/v?\d+\.\d+\.\d+/, '')
    end
  end
end
##[<] 🤖🤖
