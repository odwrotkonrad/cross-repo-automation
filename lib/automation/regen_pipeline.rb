##[>] 🤖🤖
require 'json'

module Automation
  # RegenPipeline renders handler jobs as the child pipeline YAML regen-fan-out runs.
  module RegenPipeline
    Job = Struct.new(:repo, :key, :tag, :prev, :record_only, keyword_init: true)
    GraphJob = Struct.new(:kinds, :moved, keyword_init: true)
    VarsJob = Struct.new(:artifact, :key, :tag, :prev, keyword_init: true)
    DesiredJob = Struct.new(:versions, :moved, keyword_init: true)

    IMAGE = '$ARTIFACT_REGISTRY/ci-linux:$OCI_IMAGES_CI_LINUX_REF'
    RUNNER_TAG = 'gke-linux-amd64-small'

    HEADER = <<~YAML
      stages: [regen]
      variables:
        ARTIFACT_REGISTRY: $GRP_KO_VAR_ARTIFACT_REGISTRY
        OCI_IMAGES_CI_LINUX_REF: $GRP_KO_VAR_OCI_IMAGES_CI_LINUX_REF
        TOOLS_CONFIGS_REF: $GRP_KO_VAR_TOOLS_CONFIGS_REF
        AI_TOOLS_CONFIGS_REF: $GRP_KO_VAR_AI_TOOLS_CONFIGS_REF
        AUTOMATION_REF: $GRP_KO_VAR_AUTOMATION_REF
        MISC_REF: $GRP_KO_VAR_MISC_REF
        PROSE_ASSETS_REF: $GRP_KO_VAR_PROSE_ASSETS_REF
        PROSE_SPEC_REF: $GRP_KO_VAR_PROSE_SPEC_REF
        CHE_PACKAGES_REF: $GRP_KO_VAR_CHE_PACKAGES_REF
        IAC_REF: $GRP_KO_VAR_IAC_REF
    YAML

    def self.render(jobs, empty_reason:)
      body = jobs.empty? ? noop(empty_reason) : jobs.map { |j| job_yaml(j) }.join
      HEADER + body
    end

    def self.job_yaml(job)
      case job
      when GraphJob then graph(job)
      when VarsJob then vars(job)
      when DesiredJob then desired(job)
      else regen(job)
      end
    end

    def self.regen(job)
      script = "bin/automation regen --repo #{job.repo} --key #{job.key} --tag #{job.tag}"
      script += " --prev #{job.prev}" if job.prev
      script += ' --record-only' if job.record_only
      wrap("regen:#{job.repo}:#{job.key}", script, token: true)
    end

    def self.graph(job)
      wrap("graph:#{job.kinds.join('+')}", "bin/automation graph-write --kinds #{job.kinds.join(',')} --moved #{job.moved.inspect}", token: true)
    end

    #[why] the payload is one version per artifact per consumer, past what a command line holds:
    #   the job writes it to a file and the CLI reads it back
    def self.desired(job)
      payload = job.versions.to_json.gsub("'", %q('"'"'))
      script = "printf '%s' '#{payload}' > desired-versions.json && " \
               "bin/automation desired-write --versions desired-versions.json --moved #{job.moved.inspect}"
      wrap('graph:desired', script, token: true)
    end

    def self.vars(job)
      script = "bin/automation vars-write --artifact #{job.artifact} --key #{job.key} --tag #{job.tag}"
      script += " --prev #{job.prev}" if job.prev
      wrap("vars:#{job.key}", script, token: true)
    end

    #[why] shared/ci/ruby is gitignored, rendered from cross-repo/misc, so a child pipeline's clean
    #   checkout does not carry it and `require 'artifact'` in lib/automation.rb raises LoadError.
    #   The parent jobs get it for free because `make aggregate` runs che first; a generated job
    #   calls bin/automation directly, so it renders the payload itself
    BOOTSTRAP = 'che render-templates --profiles=bootstrapCrossRepoCI'.freeze

    def self.wrap(name, script, token:)
      credentials = token ? "  variables:\n    AUTOMATION_GITLAB_TOKEN: $REPO_PROTECTED_VAR_BOT_AUTOMATION_GITLAB_TOKEN\n    AUTOMATION_REVIEWER: $REPO_VAR_AUTOMATION_REVIEWER\n" : ''
      <<~YAML
        #{name}:
          stage: regen
          image: #{IMAGE}
          tags:
            - #{RUNNER_TAG}
        #{credentials.chomp}
          script:
            - #{BOOTSTRAP.to_json}
            - #{script.to_json}
      YAML
    end

    def self.noop(reason)
      <<~YAML
        no-op:
          stage: regen
          image: #{IMAGE}
          tags:
            - #{RUNNER_TAG}
          script:
            - #{"echo #{reason.inspect}".to_json}
      YAML
    end
  end
end
##[<] 🤖🤖
