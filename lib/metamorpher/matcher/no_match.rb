require "attributable"

module Metamorpher
  module Matcher
    class NoMatch
      extend Attributable
      attributes

      def matches?
        false
      end

      def combine(_)
        NoMatch.new
      end
    end
  end
end
