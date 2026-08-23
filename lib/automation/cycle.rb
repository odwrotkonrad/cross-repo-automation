##[>] 🤖🤖
module Automation
  # Cycle finds a circular dependency in a depends_on map, naming the full path it closes on.
  module Cycle
    # Returns every cycle as a path list, empty when the graph is acyclic.
    def self.find(depends_on)
      found = []
      state = Hash.new(:unseen)
      depends_on.each_key { |node| walk(node, depends_on, state, [], found) }
      found.uniq
    end

    def self.walk(node, depends_on, state, path, found)
      if state[node] == :active
        found << (path[path.index(node)..] + [node]).join(' -> ')
        return
      end
      return if state[node] == :done

      state[node] = :active
      depends_on.fetch(node, []).each { |up| walk(up, depends_on, state, path + [node], found) }
      state[node] = :done
    end
  end
end
##[<] 🤖🤖
