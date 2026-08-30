##[>] 🤖🤖
module Automation
  # Pin is one variable carrying an artifact's version into a scope, its key read from the artifact.
  Pin = Struct.new(:repo, :artifact, :key, :scope, keyword_init: true) do
    # The branch-name label for a variable key: CENTRALIZED_ASSETS_GENERIC_REF -> centralized-assets-generic.
    def self.label_of(key)
      key.delete_suffix('_REF').downcase.tr('_', '-')
    end

    def var_key
      (scope == :group ? CrossRepo::GROUP_PREFIX : CrossRepo::PROJECT_PREFIX) + key
    end
  end
end
##[<] 🤖🤖
