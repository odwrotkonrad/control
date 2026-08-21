##[>] 🤖🤖
require 'yaml'

module Automation
  # Graph answers consumer and producer queries over deps/deps-graph.yml.
  class Graph
    def self.load(path)
      new(YAML.safe_load(File.read(path, encoding: "UTF-8")))
    end

    def initialize(doc)
      @artifacts = doc.fetch('repositories').to_h do |r|
        [r.fetch('repo'), (r['artifacts'] || []).map { |a| a.fetch('name') }]
      end
      @edges = doc['edges'] || {}
    end

    def repos
      @artifacts.keys
    end

    def produces(repo)
      @artifacts.fetch(repo, [])
    end

    def consumes(repo)
      @edges.select { |_, downs| downs.any? { |v| within?(v, repo) } }.keys.sort
    end

    # Repos consuming any artifact at or under +vertex+, the vertex's own repo excluded.
    def affected(vertex)
      @edges
        .select { |up, _| within?(up, vertex) }
        .flat_map { |_, downs| downs.map { |v| vertex_repo(v) } }
        .compact
        .reject { |r| r == vertex || within?(vertex, r) }
        .uniq
        .sort
    end

    private

    def within?(vertex, prefix)
      vertex == prefix || vertex.start_with?("#{prefix}/")
    end

    def vertex_repo(vertex)
      parts = vertex.split('/')
      parts.size.downto(1) do |n|
        candidate = parts.first(n).join('/')
        return candidate if @artifacts.key?(candidate)
      end
      nil
    end
  end
end
##[<] 🤖🤖
