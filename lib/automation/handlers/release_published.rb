##[>] 🤖🤖
module Automation
  module Handlers
    # ReleasePublished answers a producer release with one pin regen per repo publishing a variable from it.
    module ReleasePublished
      def self.call(event, graph:)
        artifact = event.details['artifact']
        pins = graph.pins_for_release(artifact)
        raise ArgumentError, "no ci-var artifact in the graph is fed by #{artifact}" if pins.empty?

        pins.map { |p| [p.repo, p.key] }.uniq.map do |repo, key|
          RegenPipeline::Job.new(repo: repo, key: key, tag: event.tag, prev: event.details['prev'])
        end
      end
    end
  end
end
##[<] 🤖🤖
