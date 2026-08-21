##[>] 🤖🤖
module Automation
  module Handlers
    # ReleasePublished answers a producer release with the iac pin regen, or the consumers when iac holds no pin for it.
    module ReleasePublished
      PIN_REPO = 'cross-repo/infra/iac'

      def self.call(event, graph:, producers:)
        d = event.details
        producer = producers.fetch(d['producer']) { raise ArgumentError, "unknown producer #{d['producer'].inspect}" }
        repos = producer.var_key ? [PIN_REPO] : graph.affected(d['artifact'])
        repos.map { |r| RegenPipeline::Job.new(repo: r, producer: producer.name, tag: d['tag'], prev: d['prev']) }
      end
    end
  end
end
##[<] 🤖🤖
