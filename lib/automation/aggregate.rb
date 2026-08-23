##[>] 🤖🤖
require 'yaml'
require_relative 'cycle'

module Automation
  # Aggregate merges every repo's .repo/ declarations into the system graph files.
  module Aggregate
    GRAPH_PATH = '.repo/dependency-graph.yml'
    PRODUCED_PATH = '.repo/artifacts-produced.yml'
    CONSUMED_PATH = '.repo/artifacts-consumed.yml'
    PATHS = [GRAPH_PATH, PRODUCED_PATH, CONSUMED_PATH].freeze

    #[why] desired is absent: ci-variables owns it, publishing it from the variables it applies.
    #   Aggregation runs with no GitLab token, so it cannot read the applied state.
    FILES = { artifacts: 'artifacts.yml', latest: 'latest-artifacts.yml', edges: 'dependency-graph.yml',
              current: 'current-dependency-graph.yml' }.freeze
    DESIRED_FILE = 'desired-dependency-graph.yml'.freeze

    def self.combine(seeds, declared)
      seeds.merge(declared)
    end

    STATIC_FIELDS = %w[type versionEnvVar].freeze
    NON_ARTIFACT_KEYS = %w[ciEnv devEnv repoContents].freeze

    # Every artifact definition across repos, keyed by uri, the first declaration winning.
    def self.artifacts(repos)
      definitions(repos).transform_values { |variants| variants.first.last }
    end

    # Each uri mapped to every [repo, definition] pair producing it, so disagreement stays visible.
    def self.definitions(repos)
      repos.sort.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(repo, r), all|
        (r['produces'] || []).each { |e| all[e.fetch('uri')] << [repo, e.slice(*STATIC_FIELDS)] }
      end
    end

    # Merges every repo's dependsOn block, the keys being globally unique by construction.
    def self.edges(repos)
      repos.sort.each_with_object({}) do |(_repo, r), merged|
        (r['dependsOn'] || {}).except(*NON_ARTIFACT_KEYS).each do |uri, ups|
          merged[uri] = (merged[uri] || []) | Array(ups).map { |u| u.is_a?(Hash) ? u.fetch('uri') : u }
        end
      end.sort.to_h { |uri, ups| [uri, ups.sort] }
    end

    def self.produced(repos)
      repos.flat_map { |repo, r| (r['produces'] || []).map { |e| [e.fetch('uri'), repo, e['version']] } }
    end

    def self.consumed(repos)
      repos.flat_map { |repo, r| (r['consumes'] || []).map { |e| [e.fetch('uri'), repo, e['version']] } }
    end

    def self.inconsistencies(repos)
      all = artifacts(repos)
      missing = definition_conflicts(definitions(repos)) + reference_gaps(repos, all) + variable_conflicts(all)
      producers = produced(repos).group_by(&:first)
      producers.each do |uri, entries|
        repos_claiming = entries.map { |e| e[1] }.uniq
        missing << "#{uri} is produced by #{repos_claiming.join(' and ')}, an artifact has exactly one producer" if repos_claiming.size > 1
      end
      consumed(repos).each do |uri, repo, _|
        missing << "#{repo} consumes #{uri}, which no repo produces" unless producers.key?(uri)
      end
      missing.concat(foreign_edge_keys(repos))
      missing.concat(uncovered(repos))
      missing.concat(Cycle.find(edges(repos)).map { |c| "cycle: #{c}" })
      missing.uniq
    end

    #[why] a dependsOn key names what this repo builds, so it is one of its own produced artifacts or
    #   a reserved environment key: keying an edge on something the repo merely consumes would claim
    #   authorship of another repo's artifact and hang its upstreams off the wrong vertex
    def self.foreign_edge_keys(repos)
      repos.flat_map do |repo, r|
        mine = (r['produces'] || []).map { |e| e.fetch('uri') }
        ((r['dependsOn'] || {}).keys - NON_ARTIFACT_KEYS - mine)
          .map { |uri| "#{repo} keys a dependsOn edge on #{uri}, which it does not produce" }
      end
    end

    # Two repos defining one uri must agree on every static field.
    def self.definition_conflicts(defs)
      defs.filter_map do |uri, variants|
        next if variants.map(&:last).uniq.size < 2

        "#{uri} is defined differently by #{variants.map(&:first).join(' and ')}"
      end
    end

    # A produced, consumed or dependsOn reference to a uri no repo produces.
    def self.reference_gaps(repos, all)
      repos.sort.flat_map do |repo, r|
        edges = r['dependsOn'] || {}
        referenced = (r['produces'] || []).map { |e| e['uri'] } + (r['consumes'] || []).map { |e| e['uri'] } +
                     (edges.keys - NON_ARTIFACT_KEYS) + edges.values.flatten.map { |u| u.is_a?(Hash) ? u['uri'] : u }
        referenced.uniq.reject { |uri| all.key?(uri) }.map { |uri| "#{repo} references #{uri}, which no repo produces" }
      end
    end

    # Every versionEnvVar must name exactly one artifact: the check that catches shared refs.
    def self.variable_conflicts(all)
      all.group_by { |_uri, doc| doc['versionEnvVar'] }.filter_map do |var, entries|
        next if var.nil? || entries.size < 2

        "versionEnvVar #{var} names #{entries.size} artifacts: #{entries.map(&:first).sort.join(' ')}"
      end
    end

    # Artifacts this repo produces without a dependsOn key, the migration work queue.
    def self.undeclared(repos)
      repos.sort.flat_map do |repo, r|
        declared = (r['dependsOn'] || {}).keys
        (r['produces'] || []).map { |e| e.fetch('uri') }.reject { |uri| declared.include?(uri) }
                             .map { |uri| "#{repo} produces #{uri} with no dependsOn entry" }
      end
    end

    # Consumed artifacts no dependsOn edge accounts for: an upstream nothing in the repo builds from.
    def self.uncovered(repos)
      repos.sort.flat_map do |repo, r|
        covered = (r['dependsOn'] || {}).values.flatten.map { |u| u.is_a?(Hash) ? u['uri'] : u }
        (r['consumes'] || []).map { |e| e.fetch('uri') }.reject { |uri| covered.include?(uri) }
                             .map { |uri| "#{repo} consumes #{uri}, which no dependsOn edge names" }
      end
    end

    def self.render(repos, kind:)
      case kind
      when :artifacts then render_artifacts(repos)
      when :latest then render_latest(repos)
      when :edges then render_edges(repos)
      when :current then render_versioned_edges(repos)
      else raise ArgumentError, "unknown graph kind #{kind.inspect}"
      end
    end

    def self.wrap(lines)
      "#{['##[>] 🤖', *lines, '##[<] 🤖'].join("\n")}\n"
    end

    # Identity alone: the one file stating an artifact's type and variable.
    def self.render_artifacts(repos)
      lines = ['artifacts:']
      artifacts(repos).sort.each do |uri, doc|
        lines << "  #{uri}:"
        STATIC_FIELDS.each { |k| lines << "    #{k}: #{doc[k]}" }
      end
      wrap(lines)
    end

    # The latest published version per artifact, as its own producer records it.
    def self.render_latest(repos)
      versions = produced(repos).each_with_object({}) { |(uri, _repo, version), all| all[uri] ||= version }
      wrap(['versions:', *versions.sort.map { |uri, version| "  #{uri}: #{version || 'unknown'}" }])
    end

    # The unversioned shape: which artifact is built from which, and nothing else.
    def self.render_edges(repos)
      lines = ['dependsOn:']
      edges(repos).each do |uri, ups|
        lines << "  #{uri}:#{ups.empty? ? ' []' : ''}"
        ups.each { |up| lines << "    - #{up}" }
      end
      wrap(lines)
    end

    #[why] one entry per consuming repo, never one per artifact: three repos pin lib independently,
    #   and a lagging repo is exactly the line the file exists to show
    def self.render_versioned_edges(repos, held: nil, fallback: {})
      held ||= versions_by_repo(repos)
      producers = produced(repos).to_h { |uri, repo, _| [uri, repo] }
      lines = ['dependsOn:']
      edges(repos).each do |uri, ups|
        repo = producers[uri]
        lines << "  #{uri}:#{ups.empty? ? ' []' : ''}"
        ups.each { |up| lines << "    - {artifact: #{up}, version: #{held.dig(repo, up) || fallback[up] || 'unknown'}}" }
      end
      wrap(lines)
    end

    #[why] the desired graph: the same edges, versioned by what ci-variables applied rather than what
    #   repos hold. A consumer with no project variable for an upstream falls back to the group scope,
    #   which is the precedence GitLab itself applies.
    GROUP_SCOPE = 'group'.freeze

    def self.render_desired(repos, versions)
      by_var = artifacts(repos).to_h { |uri, doc| [doc['versionEnvVar'], uri] }.except(nil)
      held = versions.to_h { |repo, vars| [repo, vars.to_h { |key, v| [by_var[key], v] }.except(nil)] }
      render_versioned_edges(repos, held: held, fallback: held[GROUP_SCOPE] || {})
    end

    # Each repo's own pins, uncollapsed: {repo => {uri => version}}.
    def self.versions_by_repo(repos)
      consumed(repos).each_with_object(Hash.new { |h, k| h[k] = {} }) do |(uri, repo, version), all|
        all[repo][uri] ||= version
      end
    end

    def self.declared_local(workspace)
      Dir.glob(File.join(workspace, '**', GRAPH_PATH)).map { |f| f.delete_prefix("#{workspace}/").delete_suffix("/#{GRAPH_PATH}") }
    end

    # Reads one repo's three declaration files, merging them into the single shape the graph consumes.
    def self.read_local(root)
      PATHS.each_with_object({}) do |rel, doc|
        path = File.join(root, rel)
        doc.merge!(YAML.safe_load(File.read(path, encoding: 'UTF-8')) || {}) if File.file?(path)
      end
    end

    def self.read_remote(group, repo, fetcher)
      PATHS.each_with_object({}) do |rel, doc|
        body = fetcher.call(group, repo, rel)
        doc.merge!(YAML.safe_load(body) || {}) if body
      end
    end

    # Reads every repo's declarations over the seeds, the one input the graph and tfvars derive from.
    #[why] the seed file shrinks to nothing as repos declare their own interfaces: an absent one
    #   is the finished state, not an error
    def self.collect(seed_file:, group:, local: nil, own: nil, fetcher: nil)
      seeds = seed_file && File.file?(seed_file) ? YAML.safe_load(File.read(seed_file, encoding: 'UTF-8')).fetch('repos') : {}
      candidates = (seeds.keys + (local ? declared_local(local) : CrossRepo::Gitlab.projects(group))).uniq.sort
      declared = candidates.to_h do |repo|
        doc = local ? read_local(File.join(local, repo)) : read_remote(group, repo, fetcher)
        [repo, doc.empty? ? nil : doc]
      end.compact
      declared[own[:repo]] = read_local(own[:root]) if own && Dir.exist?(File.join(own[:root], '.repo'))
      [combine(seeds, declared), declared, candidates.size - declared.size]
    end

    def self.run(seed_file:, graph_dir:, check:, group:, local: nil, own: nil, fetcher: nil)
      repos, declared, seeded = collect(seed_file: seed_file, group: group, local: local, own: own, fetcher: fetcher)

      missing = inconsistencies(repos)
      abort(['inconsistent interfaces:', *missing].join("\n")) unless missing.empty?
      undeclared(repos).each { |w| warn "warning: #{w}" }

      write_graphs(repos, graph_dir: graph_dir, check: check, declared: declared, seeded: seeded)
    end

    def self.write_graphs(repos, graph_dir:, check:, declared:, seeded:)
      summary = "declared: #{declared.empty? ? 'none' : declared.keys.join(' ')}, seeded: #{seeded} repos"
      drifted = FILES.filter_map do |kind, name|
        generated = render(repos, kind: kind)
        path = File.join(graph_dir, name)
        if check
          current = File.file?(path) ? File.read(path, encoding: 'UTF-8') : ''
          next name if current != generated

          nil
        else
          File.write(path, generated)
          nil
        end
      end
      abort("#{drifted.join(', ')} drifted, rerun bin/automation aggregate") unless drifted.empty?
      puts check ? "system graph in sync (#{summary})" : "wrote #{FILES.values.join(' ')} (#{summary})"
    end
  end
end
##[<] 🤖🤖
