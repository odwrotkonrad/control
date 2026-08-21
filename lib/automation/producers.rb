##[>] 🤖🤖
module Automation
  # Producer is a repo whose release is pinned by iac as the +var_key+ group variable.
  Producer = Struct.new(:name, :var_key, :artifact, keyword_init: true)

  PRODUCERS = [
    Producer.new(name: 'prose-assets', var_key: 'GRP_KO_VAR_PROSE_ASSETS_REF', artifact: 'cross-repo/prose/assets'),
    Producer.new(name: 'prose-spec', var_key: 'GRP_KO_VAR_PROSE_SPEC_REF', artifact: 'cross-repo/prose/spec'),
    Producer.new(name: 'misc', var_key: 'GRP_KO_VAR_MISC_REF', artifact: 'cross-repo/misc'),
    Producer.new(name: 'che-packages', var_key: 'GRP_KO_VAR_CHE_PACKAGES_REF', artifact: 'che-packages/catalog'),
    Producer.new(name: 'oci-images', var_key: 'GRP_KO_VAR_CI_IMAGES_REF', artifact: 'cross-repo/infra/oci-images/ci-linux')
  ].to_h { |p| [p.name, p] }.freeze
end
##[<] 🤖🤖
