##[>] 🤖
downstream:
  - uri: gitlab.com/konradodwrot/cross-repo/automation
    type: gitRepository
    versionEnvVar: AUTOMATION_REF
    version: {{ env.Getenv "AUTOMATION_REF" }}
##[<] 🤖
