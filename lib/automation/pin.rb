##[>] 🤖🤖
module Automation
  # Pin is a group variable +repo+ publishes from the upstream +source+, named by its ci-var/<name> graph artifact.
  Pin = Struct.new(:repo, :artifact, :source, keyword_init: true) do
    VAR_PREFIX = 'GRP_KO_VAR_'
    ARTIFACT_PREFIX = 'ci-var/'

    def self.artifact?(vertex)
      vertex.include?("/#{ARTIFACT_PREFIX}")
    end

    def self.key_of(artifact)
      artifact.delete_prefix(ARTIFACT_PREFIX).upcase.tr('-', '_')
    end

    def self.label_of(key)
      key.delete_suffix('_REF').downcase.tr('_', '-')
    end

    def key
      Pin.key_of(artifact)
    end

    def var_key
      VAR_PREFIX + key
    end
  end
end
##[<] 🤖🤖
