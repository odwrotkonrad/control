##[>] 🤖🤖
module Automation
  module Handlers
    # CiVarChanged answers applied group variables with a content regen per consumer of each variable's sources.
    module CiVarChanged
      def self.call(event, graph:)
        event.details['variables'].flat_map do |change|
          pins = graph.pins_for_var(change['key'])
          next [] if pins.empty?

          publishers = pins.map(&:repo)
          consumers = pins.flat_map { |p| graph.affected(p.source) }.uniq.sort - publishers
          consumers.map { |r| RegenPipeline::Job.new(repo: r, key: pins.first.key, tag: change['to'], prev: change['from']) }
        end
      end
    end
  end
end
##[<] 🤖🤖
