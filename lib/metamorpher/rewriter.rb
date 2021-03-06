require "metamorpher/rewriter/rule"

module Metamorpher
  module Rewriter
    extend Forwardable
    def_delegators :rule, :apply, :reduce

    def rule
      @rule ||= Rewriter::Rule.new(pattern: pattern, replacement: replacement)
    end
  end
end
