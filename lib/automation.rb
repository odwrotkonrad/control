##[>] 🤖🤖
require_relative 'automation/event'
require_relative 'automation/producers'
require_relative 'automation/graph'
require_relative 'automation/regen_pipeline'
require_relative 'automation/handlers/release_published'
require_relative 'automation/handlers/ci_var_changed'

# Automation turns one CI event into the child pipeline that regenerates the affected repos.
module Automation
  HANDLERS = {
    'release.published' => Handlers::ReleasePublished,
    'ci-var.changed' => Handlers::CiVarChanged
  }.freeze

  # Returns the child pipeline YAML answering +event+ over +graph+.
  def self.dispatch(event, graph:, producers: PRODUCERS)
    handler = HANDLERS.fetch(event.type)
    jobs = handler.call(event, graph: graph, producers: producers)
    RegenPipeline.render(jobs, empty_reason: "#{event.type} #{event.summary}: no affected downstreams")
  end
end
##[<] 🤖🤖
