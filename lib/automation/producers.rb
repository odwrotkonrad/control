##[>] 🤖🤖
module Automation
  # Producer is a repo whose release iac pins as the +var_key+ group variable, exported to renders as +env_var+.
  Producer = Struct.new(:name, :var_key, :artifact, :env_var, :bare_pin, keyword_init: true) do
    def pin_key
      var_key.delete_prefix('GRP_KO_VAR_')
    end

    def pin_written(tag)
      bare_pin ? tag.delete_prefix('v') : tag
    end
  end

  PRODUCERS = [
    Producer.new(name: 'prose-assets', var_key: 'GRP_KO_VAR_PROSE_ASSETS_REF', artifact: 'cross-repo/prose/assets', env_var: 'PROSE_ASSETS_REF'),
    Producer.new(name: 'prose-spec', var_key: 'GRP_KO_VAR_PROSE_SPEC_REF', artifact: 'cross-repo/prose/spec', env_var: 'PROSE_SPEC_REF'),
    Producer.new(name: 'misc', var_key: 'GRP_KO_VAR_MISC_REF', artifact: 'cross-repo/misc', env_var: 'MISC_REF'),
    Producer.new(name: 'che-packages', var_key: 'GRP_KO_VAR_CHE_PACKAGES_REF', artifact: 'che-packages/catalog', bare_pin: true),
    Producer.new(name: 'oci-images', var_key: 'GRP_KO_VAR_CI_IMAGES_REF', artifact: 'cross-repo/infra/oci-images/ci-linux')
  ].to_h { |p| [p.name, p] }.freeze
end
##[<] 🤖🤖
