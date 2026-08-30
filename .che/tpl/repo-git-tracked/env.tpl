##[>] 🤖🤖
##[>] dependencies
{{ localFile ".repo/upstream.env" | dependency }}
##[<] dependencies
ARTIFACT_REGISTRY={{ shell "glab variable get -g konradodwrot GRP_KO_VAR_ARTIFACT_REGISTRY" }}
AUTOMATION_GITLAB_TOKEN={{ shell "glab variable get -R konradodwrot/cross-repo/automation REPO_PROTECTED_VAR_BOT_AUTOMATION_GITLAB_TOKEN" }}
TAG_TOKEN={{ shell "glab variable get -R konradodwrot/cross-repo/automation REPO_PROTECTED_VAR_BOT_TAG_TOKEN" }}
AUTOMATION_REVIEWER={{ shell "glab variable get -R konradodwrot/cross-repo/automation REPO_VAR_AUTOMATION_REVIEWER 2>/dev/null || echo konradodwrot" }}
##[<] 🤖🤖
