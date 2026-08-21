##[>] 🤖🤖
require 'json'

module Automation
  # RegenPipeline renders regen jobs as the child pipeline YAML regen-fan-out runs.
  module RegenPipeline
    Job = Struct.new(:repo, :key, :tag, :prev, keyword_init: true)

    IMAGE = '$ARTIFACT_REGISTRY/ci-linux:$CI_IMAGES_REF'
    RUNNER_TAG = 'gke-linux-amd64-small'

    HEADER = <<~YAML
      stages: [regen]
      variables:
        ARTIFACT_REGISTRY: $GRP_KO_VAR_ARTIFACT_REGISTRY
        CI_IMAGES_REF: $GRP_KO_VAR_CI_IMAGES_REF
    YAML

    def self.render(jobs, empty_reason:)
      body = jobs.empty? ? noop(empty_reason) : jobs.map { |j| regen(j) }.join
      HEADER + body
    end

    def self.regen(job)
      script = "bin/automation regen --repo #{job.repo} --key #{job.key} --tag #{job.tag}"
      script += " --prev #{job.prev}" if job.prev
      <<~YAML
        regen:#{job.repo}:#{job.key}:
          stage: regen
          image: #{IMAGE}
          tags:
            - #{RUNNER_TAG}
          variables:
            CONTROL_GITLAB_TOKEN: $REPO_VAR_CONTROL_GITLAB_TOKEN
          script:
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
