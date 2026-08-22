##[>] 🤖🤖
PROSE_ASSETS_REF={{ shell "glab variable get -g konradodwrot GRP_KO_VAR_PROSE_ASSETS_REF" }}
PROSE_SPEC_REF={{ shell "glab variable get -g konradodwrot GRP_KO_VAR_PROSE_SPEC_REF" }}
CONFIGS_REF={{ shell "glab variable get -g konradodwrot GRP_KO_VAR_CONFIGS_REF" }}
MISC_REF={{ shell "glab variable get -g konradodwrot GRP_KO_VAR_MISC_REF" }}
ARTIFACT_REGISTRY={{ shell "glab variable get -g konradodwrot GRP_KO_VAR_ARTIFACT_REGISTRY" }}
CI_IMAGES_REF={{ shell "glab variable get -g konradodwrot GRP_KO_VAR_CI_IMAGES_REF" }}
AUTOMATION_GITLAB_TOKEN={{ shell "glab variable get -R konradodwrot/cross-repo/automation REPO_VAR_AUTOMATION_GITLAB_TOKEN 2>/dev/null || glab variable get -R konradodwrot/cross-repo/automation REPO_VAR_CONTROL_GITLAB_TOKEN" }}
TAG_TOKEN={{ shell "glab variable get -R konradodwrot/cross-repo/automation REPO_VAR_TAG_TOKEN" }}
AUTOMATION_REVIEWER={{ shell "glab variable get -R konradodwrot/cross-repo/automation REPO_VAR_AUTOMATION_REVIEWER 2>/dev/null || echo konradodwrot" }}
##[<] 🤖🤖
