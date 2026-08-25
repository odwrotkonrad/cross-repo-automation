##[>] 🤖🤖
PROSE_ASSETS_REF={{ shell "glab variable get -g konradodwrot GRP_KO_VAR_PROSE_ASSETS_REF" }}
PROSE_SPEC_REF={{ shell "glab variable get -g konradodwrot GRP_KO_VAR_PROSE_SPEC_REF" }}
AI_CONFIGS_REF={{ shell "glab variable get -g konradodwrot GRP_KO_VAR_AI_CONFIGS_REF" }}
MISC_REF={{ shell "glab variable get -g konradodwrot GRP_KO_VAR_MISC_REF" }}
ARTIFACT_REGISTRY={{ shell "glab variable get -g konradodwrot GRP_KO_VAR_ARTIFACT_REGISTRY" }}
OCI_IMAGES_CI_LINUX_REF={{ shell "glab variable get -g konradodwrot GRP_KO_VAR_OCI_IMAGES_CI_LINUX_REF" }}
CHE_SCHEMA_REF={{ shell "glab variable get -g konradodwrot GRP_KO_VAR_CHE_SCHEMA_REF" }}
AUTOMATION_GITLAB_TOKEN={{ shell "glab variable get -R konradodwrot/cross-repo/automation REPO_PROTECTED_VAR_BOT_AUTOMATION_GITLAB_TOKEN" }}
TAG_TOKEN={{ shell "glab variable get -R konradodwrot/cross-repo/automation REPO_PROTECTED_VAR_BOT_TAG_TOKEN" }}
AUTOMATION_REVIEWER={{ shell "glab variable get -R konradodwrot/cross-repo/automation REPO_VAR_AUTOMATION_REVIEWER 2>/dev/null || echo konradodwrot" }}
##[<] 🤖🤖
