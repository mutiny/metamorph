require "metamorpher/refactorer/merger"
require "metamorpher/refactorer/site"
require "metamorpher/builder"
require "metamorpher/rewriter/rule"
require "metamorpher/drivers/ruby"

module Metamorpher
  module Refactorer
    def refactor(src, &block)
      literal = driver.parse(src)
      replacements = reduce_to_replacements(src, literal)
      Merger.new(src).merge(*replacements, &block)
    end

    def refactor_file(path, &block)
      refactor(File.read(path), &block)
    end

    def refactor_files(paths, &block)
      paths.reduce({}) do |result, path|
        changes = []
        result[path] = refactor_file(path) { |change| changes << change }
        block.call(path, result[path], changes) if block
        result
      end
    end

    def builder
      @builder ||= Builder.new
    end

    def driver
      @driver ||= Metamorpher::Drivers::Ruby.new
    end

    private

    def reduce_to_replacements(src, literal)
      [].tap do |replacements|
        rule.reduce(literal) do |original, rewritten|
          original_position = driver.source_location_for(original)
          original_code = src[original_position]
          refactored_code = driver.unparse(rewritten)
          replacements << Site.new(original_position, original_code, refactored_code)
        end
      end
    end

    def rule
      @rule ||= Rewriter::Rule.new(pattern: pattern, replacement: replacement)
    end
  end
end
