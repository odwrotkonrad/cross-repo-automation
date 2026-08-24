##[>] 🤖🤖
require_relative 'repo_writer'
require_relative 'aggregate'

module Automation
  # GraphWriter commits a regenerated system graph file to the graph repo, one commit per change.
  module GraphWriter
    REPO = 'cross-repo/graph'

    # The fixed commit template: the line a human reads in the graph repo's log.
    def self.message(kind, moved)
      "[graph] #{kind}: #{moved}"
    end

    # Regenerates +kinds+ from +repos+ and commits whichever moved.
    def self.write(repos, kinds:, moved:, group: 'konradodwrot', writer: nil, dry_run: false)
      writer ||= RepoWriter.new(repo: REPO, group: group, dry_run: dry_run)
      files = kinds.to_h { |kind| [Aggregate::FILES.fetch(kind), Aggregate.render(repos, kind: kind)] }
      writer.write(files, message: message(kinds.map(&:to_s).join('+'), moved))
    end

    # Commits the desired graph, whose versions come from ci-variables rather than the repos.
    def self.write_desired(repos, versions:, moved:, group: 'konradodwrot', writer: nil, dry_run: false)
      writer ||= RepoWriter.new(repo: REPO, group: group, dry_run: dry_run)
      writer.write({ Aggregate::DESIRED_FILE => Aggregate.render_desired(repos, versions) },
                   message: message('desired', moved))
    end
  end
end
##[<] 🤖🤖
