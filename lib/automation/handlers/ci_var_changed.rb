##[>] 🤖🤖
module Automation
  module Handlers
    # CiVarChanged answers iac's applied group variables with a content regen per consumer of each variable's producer.
    module CiVarChanged
      def self.call(event, graph:, producers:)
        by_key = producers.values.to_h { |p| [p.var_key, p] }
        event.details['variables'].flat_map do |change|
          producer = by_key[change['key']]
          next [] unless producer

          (graph.affected(producer.artifact) - [ReleasePublished::PIN_REPO]).map do |r|
            RegenPipeline::Job.new(repo: r, producer: producer.name, tag: change['to'], prev: change['from'])
          end
        end
      end
    end
  end
end
##[<] 🤖🤖
