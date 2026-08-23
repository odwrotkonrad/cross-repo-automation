##[>] 🤖🤖
require 'yaml'
require_relative 'pin'
require 'artifact'

module Automation
  # Graph answers artifact, consumer and dependency queries over a system graph file.
  class Graph
    def self.load(path)
      new(YAML.safe_load(File.read(path, encoding: 'UTF-8')))
    end

    # Loads artifacts.yml composed with dependency-graph.yml, plus each repo's declarations.
    def initialize(doc, repos: {})
      @artifacts = doc['artifacts'] || {}
      @depends_on = doc['dependsOn'] || {}
      @repos = repos
    end

    def artifacts
      @artifacts.keys
    end

    def repos
      @repos.keys
    end

    def definition(uri)
      @artifacts[uri]
    end

    # The bare variable name carrying this artifact's version, read rather than derived.
    def version_env_var(uri)
      @artifacts.fetch(uri, {})['versionEnvVar']
    end

    def uri_for_var(key)
      bare = key.delete_prefix(CrossRepo::GROUP_PREFIX).delete_prefix(CrossRepo::PROJECT_PREFIX)
      @artifacts.find { |_uri, doc| doc['versionEnvVar'] == bare }&.first
    end

    def produces(repo)
      (@repos.dig(repo, 'produces') || []).map { |e| e.fetch('uri') }
    end

    def consumes(repo)
      (@repos.dig(repo, 'consumes') || []).map { |e| e.fetch('uri') }
    end

    def producer_of(uri)
      @repos.find { |_repo, r| (r['produces'] || []).any? { |e| e['uri'] == uri } }&.first
    end

    # Repos consuming +uri+, whatever they do with it. The producing repo is excluded.
    def affected(uri)
      @repos.select { |_repo, r| (r['consumes'] || []).any? { |e| e['uri'] == uri } }
            .keys.reject { |repo| repo == producer_of(uri) }.sort
    end

    # Artifacts whose depends_on names +uri+: the ones an upstream release actually rebuilds.
    def affected_artifacts(uri)
      @depends_on.select { |_downstream, ups| ups.include?(uri) }.keys.sort
    end

    # Consumers that record +uri+'s version but build nothing from it.
    def record_only(uri)
      rebuilt = affected_artifacts(uri).filter_map { |a| producer_of(a) }.uniq
      affected(uri) - rebuilt
    end

    # One Pin per consumer of +uri+, naming the project variable that consumer reads.
    def pins_for(uri)
      key = version_env_var(uri)
      return [] unless key

      affected(uri).map { |repo| Pin.new(repo: repo, artifact: uri, key: key, scope: :project) }
    end
  end
end
##[<] 🤖🤖
