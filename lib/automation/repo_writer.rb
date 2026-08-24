##[>] 🤖🤖
require 'tmpdir'
require 'fileutils'

module Automation
  # RepoWriter commits generated files straight to another repo's main: clone, write, commit, push.
  class RepoWriter
    def initialize(repo:, group: 'konradodwrot', workdir: nil, dry_run: false)
      @repo = repo
      @group = group
      @workdir = workdir
      @dry_run = dry_run
    end

    attr_reader :workdir

    # Writes +files+ (path => content) and pushes one commit, a no-op when nothing changed.
    def write(files, message:)
      clone unless @workdir
      files.each do |rel, content|
        path = File.join(@workdir, rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end
      git('add', '-A')
      return "#{@repo}: no change" if Shell.ok?('git', 'diff', '--cached', '--quiet', chdir: @workdir)
      return "DRY RUN #{@repo}: would commit #{message.inspect}\n#{git('diff', '--cached', '--stat')}" if @dry_run

      identity
      git('commit', '-m', message)
      Shell.run_network('git', 'push', 'origin', 'HEAD:main', chdir: @workdir)
      "#{@repo}: committed #{message.inspect}"
    end

    private

    def git(*args)
      Shell.run('git', *args, chdir: @workdir)
    end

    def clone
      @workdir = File.join(Dir.mktmpdir, File.basename(@repo))
      Shell.run_network('git', 'clone', '--depth', '1',
                        "https://ko-automation:#{ENV.fetch('AUTOMATION_GITLAB_TOKEN')}@gitlab.com/#{@group}/#{@repo}.git", @workdir)
    end

    def identity
      git('config', 'user.name', 'ko-automation')
      git('config', 'user.email', 'automation@noreply.gitlab.com')
    end
  end
end
##[<] 🤖🤖
