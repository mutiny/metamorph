# Metamorpher [![Build Status](https://travis-ci.org/mutiny/metamorpher.svg?branch=master)](https://travis-ci.org/mutiny/metamorpher) [![Code Climate](https://codeclimate.com/github/mutiny/metamorpher/badges/gpa.svg)](https://codeclimate.com/github/mutiny/metamorpher) [![Dependency Status](https://gemnasium.com/mutiny/metamorpher.svg)](https://gemnasium.com/mutiny/metamorpher) [![Test Coverage](https://codeclimate.com/github/mutiny/metamorpher/badges/coverage.svg)](https://codeclimate.com/github/mutiny/metamorpher)

A term rewriting library for transforming (Ruby) programs.

## Basic usage

Here's a very simple example that refactors Ruby code of the form `if some_predicate then true else false end` to `some_predicate`:

```ruby
require "metamorpher"

class UnnecessaryConditionalRefactorer
  include Metamorpher::Refactorer
  include Metamorpher::Builders::Ruby

  def pattern
    builder.build("if CONDITION then true else false end")
  end

  def replacement
    builder.build("CONDITION")
  end
end

program = "result = if some_predicate then true else false end"
UnnecessaryConditionalRefactorer.new.refactor(program)
 # => "result = some_predicate"
```

This simple example is short, but terse! To fully understand it, you might now want to read about:

* [Fundamentals](#fundamentals) - Information on the core of metamorpher and the theory of term rewriting:
    * [Building terms](#building-terms) - how to create the data structure (terms) used by Rewriters and Matchers.
    * [Matchers](#matchers) - how to determine whether an expression adheres to a pattern (i.e., matches a term).
    * [Rewriters](#rewriters) - how to transform expressions into other expressions.

* [Practicalities](#practicalities) - Information on how to use metamorpher to manipulate (Ruby) programs:
    * [Building Ruby terms](#building-ruby-terms) - how to concisely create terms that represent Ruby programs.
    * [Transformers](#transformers) - how to use rewriters to transform Ruby programs.


## Fundamentals

Metamorpher is based on the theory of [term rewriting](http://www.meta-environment.org/doc/books/extraction-transformation/term-rewriting/term-rewriting.html). The following sections describe how to build terms (the key data structure used in metamorpher), how to use terms to search over programs using matchers, and how to transform parts of a program using rewriters.

**Note** that the examples in this section operate on a fictional programming language (i.e., not Ruby). For examples that manipulate Ruby programs, see the [practicalities](#practicalities) section.

### Building terms

The primary data structure used for [rewriting](#rewriters) and for [matching](#matchers) is a term. A term is a tree (i.e., an acyclic graph). The nodes of the tree are either a:

* Literal - a node of the abstract-syntax tree of a program.
* Variable - a named node, which is bound to a subterm (subtree) during [matching](#matchers).
* Greedy variable - a variable that is bound to a set of subterms during [matching](#matchers).
* Derivation - a placeholder node, which is replaced during [rewriting](#rewriters).
* Term Set - a collection of terms (potentially of mixed types).

To simplify the construction of terms, metamorpher provides the `Metamorpher::Builders::AST::Builder` class, which is demonstrated below.

```ruby
require "metamorpher"

include Metamorpher::Builder::AST

builder.literal! :succ # => succ
builder.literal! 4 # => 4

builder.variable! :n # => N
builder.greedy_variable! :n # => N+

builder.derivation! :singular do |singular, builder|
  builder.literal!(singular.name + "s")
end
 # [SINGULAR] -> ...

builder.derivation! :key, :value do |key, value, builder|
  builder.pair(key, value)
end
 # [KEY, VALUE] -> ...

 builder.either! builder.literal!(:succ), builder.variable!(:n)
 # TermSet[succ, N]
```

Variables can be conditional, in which case they are specified by passing a block:

```ruby
builder.variable!(:method) { |literal| literal.name =~ /^find_by_/ } # => METHOD?
builder.greedy_variable!(:pairs) { |literals| literals.size.even? } #=> PAIRS+?
```

#### Shorthands

The builder provides a method missing shorthand for constructing literals, variables and greedy variables:

```ruby
builder.succ # => succ
builder.N # => N
builder.N_ # => N+
```

Conditional variables can also be constructed using this shorthand:

```ruby
builder.METHOD { |literal| literal.name =~ /^find_by_/ } #=> METHOD?
builder.PAIRS_ { |literal| literal.name =~ /^find_by_/ } #=> PAIRS+?
```

#### Coercion of non-terms to literals

When constructing a literal or a term set, the builder ensures that any children are converted to literals if they are not already a term:

```ruby
builder.literal!(:add, :x, :y) # => add(x, y)
builder.add(:x, :y) # => add(x, y)
builder.either!(:add, :subtract) # => TermSet[add, subtract]
```

Without automatic coercion, the statements above would be written as follows. Note that they are more verbose:

```ruby
builder.literal!(:add, builder.literal!(:x), builder.literal!(:y)) # => add(x, y)
builder.add(builder.x, builder.y) # => add(x, y)
builder.either!(builder.add, builder.subtract) # => TermSet[add, subtract]
```

Note that coercion isn't necessary (and isn't applied) when the children of a literal are already terms:

```ruby
builder.literal!(:add, builder.variable!(:n), builder.variable!(:m)) # => add(N, M)
builder.add(builder.N, builder.M) # => add(N, M)
builder.either!(builder.N, builder.M) # => TermSet[N, M]
```

### Matchers

Matchers search for subexpressions that adhere to a specified pattern. They are used by rewriters to find transformation sites in expressions, and can also be used to search programs. For simple searches over a program's source code, a regular expression can be used. For more complicated searches, a term matching system (such as the one provided by `Metamorpher::Matcher`) is likely to be a better fit.

Metamorpher provides the `Metamorpher::Matcher` module for specifying matchers. Include it, specify a `pattern` and then call `run(expression)`:

```ruby
require "metamorpher"

# Use the AST builder
Metamorpher.configure(:ast)

class SuccZeroMatcher
  include Metamorpher::Matcher
  include Metamorpher::Builders::AST

  def pattern
    builder.succ(0)
  end
end

expression = Metamorpher.builder.succ(0) # => succ(0)
result = SuccZeroMatcher.new.run(expression)
 # => <Metamorpher::Matcher::Match root=succ(0), substitution={}>
result.matches? # => true

expression = Metamorpher.builder.succ(1) # => succ(1)
result = SuccZeroMatcher.new.run(expression)
 # => <Metamorpher::Matcher::NoMatch>
result.matches? # => false
```

#### Alternatives

Matching can search for several expressions to match at a time. Metamorpher provides TermSets for this purpose. Recall that TermSets are built using `builder.either!`

For example, we can extend our previous matcher to search for the expressions `succ(0)` and `pred(2)` at the same time.

```ruby
class VerboseOneMatcher
  include Metamorpher::Matcher
  include Metamorpher::Builders::AST

  def pattern
    builder.either!(builder.succ(0), builder.pred(2))
  end
end

expression = Metamorpher.builder.succ(0) # => succ(0)
result = VerboseOneMatcher.new.run(expression)
 # => <Metamorpher::Matcher::Match root=succ(0), substitution={}>
result.matches? # => true

expression = Metamorpher.builder.pred(2) # => pred(2)
result = VerboseOneMatcher.new.run(expression)
 # => <Metamorpher::Matcher::Match root=pred(2), substitution={}>
result.matches? # => true
```

#### Variables

Matching is more powerful when we can allow for some variability in the expressions that we wish to match. Metamorpher provides variables for this purpose.

For example, suppose we wish to match expressions of the form `succ(X)` where X could be any subexpression. The following matcher achieves this, by using a variable (`x`) to match the argument to `succ`:

```ruby
class SuccMatcher
  include Metamorpher::Matcher
  include Metamorpher::Builders::AST

  def pattern
    builder.succ(builder.X)
  end
end

expression = Metamorpher.builder.succ(0) # => succ(0)
SuccMatcher.new.run(expression)
 # => <Metamorpher::Matcher::Match root=succ(0), substitution={:x=>0}>

expression = Metamorpher.builder.succ(1) # => succ(1)
SuccMatcher.new.run(expression)
 # => <Metamorpher::Matcher::Match root=succ(0), substitution={:x=>1}>

expression = Metamorpher.builder.succ(:n) # => succ(n)
SuccMatcher.new.run(expression)
 # => <Metamorpher::Matcher::Match root=succ(n), substitution={:x=>n}>

expression = Metamorpher.builder.succ(Metamorpher.builder.succ(:n)) # => succ(succ(n))
SuccMatcher.new.run(expression)
 # => <Metamorpher::Matcher::Match root=succ(succ(n)), substitution={:x=>succ(n)}>
```

#### Conditional variables

By default, a variable matches any literal. Matching is more powerful when variables are able to match only those literals that satisfy some condition. Metamorpher provides conditional variables for this purpose.

For example, suppose that we wish to create a matcher that only matches method calls of the form `User.find_by_XXX`, but not calls to `User.find`, `User.where` or `User.find_by`. The following matcher achieves this, by using a conditional variable (`method`). Note that the condition is specified via the block passed when building the variable:

```ruby
class DynamicFinderMatcher
  include Metamorpher::Matcher
  include Metamorpher::Builders::AST

  def pattern
    builder.literal!(
      :".",
      :User,
      builder.METHOD { |literal| literal.name =~ /^find_by_/ }
    )
  end
end

expression = Metamorpher.builder.literal!(:".", :User, :find_by_name) # => .(User, find_by_name)
DynamicFinderMatcher.new.run(expression)
 # => #<Metamorpher::Matcher::Match root=.(User, find_by_name), substitution={:method=>find_by_name}>

expression = Metamorpher.builder.literal!(:".", :User, :find) # => .(User, find)
DynamicFinderMatcher.new.run(expression)
 # => #<Metamorpher::Matcher::NoMatch>
```

#### Greedy variables

Sometimes a matcher needs to be able to match an expression that contains a variable number of subexpressions. Metamorpher provides greedy variables for this purpose.

For example, suppose that we wish to create a matcher that works for an expression, `add`, that can have 1 or more children. The following matcher achieves this, by using a greedy variable (`args`).

```ruby
class MultiAddMatcher
  include Metamorpher::Matcher
  include Metamorpher::Builders::AST

  def pattern
    builder.add(
      builder.ARGS_
    )
  end
end

MultiAddMatcher.new.run(Metamorpher.builder.add(1,2))
 # => #<Metamorpher::Matcher::Match root=add(1,2), substitution={:args=>[1, 2]}>

MultiAddMatcher.new.run(Metamorpher.builder.add(1,2,3))
 # => #<Metamorpher::Matcher::Match root=add(1,2,3), substitution={:args=>[1, 2, 3]}>
```

### Rewriters

Rewriters perform small, in-place changes to an expression. They can be used for program transformations, such as refactorings. For some simple program transformations, a regular expression can be used on the program source. For more complicated transformations, a term rewriting system (such as the one provided by `Metamorpher::Rewriter`) is likely to be a better fit.

Metamorpher provides the `Metamorpher::Rewriter` module for specifying rewriters. Include it, specify a `pattern` and a `replacement`, and then call `reduce(expression)`:

```ruby
require "metamorpher"

class SuccZeroRewriter
  include Metamorpher::Rewriter
  include Metamorpher::Builders::AST

  def pattern
    builder.literal! :succ, 0
  end

  def replacement
    builder.literal! 1
  end
end

expression = Metamorpher.builder.succ(0) # => succ(0)
SuccZeroRewriter.new.reduce(expression) # => 1
```

Note that `reduce` has no effect when called on an expression that does not match `pattern`:

```ruby
expression = Metamorpher.builder.succ(1) # => succ(1)
SuccZeroRewriter.new.reduce(expression) # => succ(1)
```

A call to `reduce` will return a literal that cannot be reduced any further by this rewriter:

```ruby
expression = Metamorpher.builder.add(
  Metamorpher.builder.succ(0),
  Metamorpher.builder.succ(0)
)
 # => succ(0)

SuccZeroRewriter.new.reduce(expression) # => add(1, 1)
```

A call to `apply` will instead return a literal after a single application of the rewriter:

```ruby
SuccZeroRewriter.new.apply(expression) # => add(1, succ(0))
```

Both `reduce` and `apply` can optionally take a block, which is called immediately before the matching term is replaced with the rewritten term:

```ruby
SuccZeroRewriter.new.reduce(expression) do |matching, rewritten|
  puts "About to replace #{matching.inspect} at position #{matching.path} with #{rewritten.inspect}"
end
 # About to replace 'succ(0)' at position [0] with '1'
 # About to replace 'succ(0)' at position [1] with '1'
 # =>
```

#### Derivations

Rewriting is more powerful when we are able to adjust the expression that is substituted for a captured variable. Metamorpher provides derivations for this purpose. (You may wish to read the section on [variables](#variables) before looking at the following example).

For example, suppose that we wish to create a rewriter that pluralises any literal. The following rewriter achieves this, by using a derivation (see the implementation of `replacement`) to create a new literal after an expression has been matched. Crucially, the derivation uses data from the captured literal when building the replacement literal:

```ruby
class PluraliseRewriter
  include Metamorpher::Rewriter
  include Metamorpher::Builders::AST

  def pattern
    builder.SINGULAR
  end

  def replacement
    builder.derivation! :singular do |singular|
      builder.literal!(singular.name + "s")
    end
  end
end

PluraliseRewriter.new.apply(Metamorpher.builder.literal! "dog") # => "dogs"
```

Derivations can be based on more than one captured variable. In which case the call to `derivation!` and the block take more than one argument:

```ruby
builder.derivation! :key, :value do |key, value|
  builder.literal!(:pair, key, value)
end
```

When deriving a variable's value without changing it, there's no need to supply a block:

```ruby
builder.derivation! :value
# builder.derivation! :value { |value| value }
```

To obtain the entire match during a derivation, use the special variable `&`:

```ruby
class ReverseVariables
  include Metamorpher::Rewriter
  include Metamorpher::Builders::AST

  def pattern
    builder.literal!(:send, nil, builder.VAR)
  end

  def replacement
    builder.derivation! :& do |match|
      builder.literal(:send, match, :reverse)
    end
  end
end
```

## Practicalities

Metamorpher provides modules that can be used to simplify the transformation of Ruby programs. This section describes how to build metamorpher terms that represent Ruby programs, and how to refactor Ruby programs. [Matchers](#matchers) and [Rewriters](#rewriters) can be used to manipulate Ruby programs too.

**Note** that metamorpher is not limited to manipulating Ruby programs. For more details on how metamorpher works and its language-independent core, see the [fundamentals](#fundamentals) section.

### Building Ruby terms

To match, rewrite or refactor Ruby programs, it's necessary to create [terms](#building-terms) that represent Ruby programs. Metamorpher provides the `Metamorpher::Builders::Ruby::Builder` class to simplify this process.

Recall that term is a tree (i.e., an acyclic graph), whose nodes are either a:

* Literal - a node of the abstract-syntax tree of a program.
* Variable - a named node, which is bound to a subterm (subtree) during [matching](#matchers).
* Greedy variable - a variable that is bound to a set of subterms during [matching](#matchers).
* Derivation - a placeholder node, which is replaced during [rewriting](#rewriters).
* Term Set - a collection of terms (potentially of mixed types).

The following examples demonstrate the way in which terms can built from strings that resemble Ruby programs:

```ruby
require "metamorpher"

include Metamorpher::Builders::Ruby

builder.build("2") # => int(2)
builder.build("2 + 2") # => send(int(2), +, int(2))
```

To build terms that contain variables, use uppercase characters. To build a greedy variable, ensure the name of the variable ends with an underscore:

```ruby
builder.build("2 + ADDEND") # => send(int(2), +, ADDEND)
builder.build("hello(PARAMS_)") # => send(, hello, PARAMS+)
```

Variables can be conditional, in which case they are specified by appending a call to `ensuring`:

```ruby
builder
  .build("METHOD_CALL(:foo, :bar)")
  .ensuring(METHOD_CALL) { |m| m.name =~ /^find_by_/ }
 # => METHOD?
```

Similar, derivations can be specified by appending a call to `deriving`:

```ruby
builder
  .build("PLURAL(:foo, :bar)")
  .deriving("PLURAL", "SINGULAR") do |singular|
    builder.build(singular.name.to_s + "s")
  end
 # [SINGULAR] -> ...

builder
  .build("HASH")
  .deriving("HASH", "KEY", "VALUE") do |key, value|
    builder.build("[#{key}, #{value}]")
  end
 # [KEY, VALUE] -> ...
```

To build a term sets, provide several arguments:

```ruby
builder.build("true", "false") # => TermSet[true, false]
```

### Transformers

Transformers are [rewriters](#rewriters) that are specialised for rewriting program source code. A transformer parses a program's source code, rewrites the source code, and returns the unparsed, rewritten source code.

Metamorpher provides two types of transformers:

* Refactorer - produces a single transformed program that contains all rewritings together
* Mutator - produces a set of transformed programs where each program contains a single rewriting

For example, for the pattern `1 + 1`, the replacement `2` and the input program `(1 + 1) * (1 + 1)`:

* A refactorer will produce `(2) * (2)`
* A mutator will produce `[(2) * (1 + 1), (1 + 1) * (2)].`

Metamorpher provides the `Metamorpher::Refactorer` and `Metamorpher::Mutator` modules for constructing classes that perform refactorings or mutations.

To construct a refactorer, include the relevant module, specify a `pattern` and a `replacement`, and then call `refactor(src)`:

```ruby
require "metamorpher"

class UnnecessaryConditionalRefactorer
  include Metamorpher::Refactorer
  include Metamorpher::Builders::Ruby

  def pattern
    builder.build("if CONDITION then true else false end")
  end

  def replacement
    builder.build("CONDITION")
  end
end

program = "a = if some_predicate then true else false end; " \
          "b = if another_predicate then true else false end"
UnnecessaryConditionalRefactorer.new.refactor(program)
 # => "a = some_predicate; b = another_predicate"
```

Similarly to construct a mutator, include the relevant module, specify a `pattern` and an array of `replacements`, and then call `mutate(src)`:

```ruby
require "metamorpher"

class LessThanMutator
  include Metamorpher::Mutator
  include Metamorpher::Builders::Ruby

  def pattern
    builder.build("A < B")
  end

  def replacements
    builder.build("A > B", "A == B")
  end
end

program = "a = foo < bar; b = bar < baz"
LessThanMutator.new.mutate(program)
 # => [
 #       "a = foo > bar; b = bar < baz",
 #       "a = foo == bar; b = bar < baz",
 #       "a = foo < bar; b = bar > baz",
 #      "a = foo < bar; b = bar == baz"
 #    ]
```

The remainder of this section discusses only refactorers, but note that mutators have all of the same functionality as refactorers (but provides methods prefixed with `mutate` rather than `refactor`).

The `refactor` method can optionally take a block, which is called immediately before the matching code is replaced with the refactored code:

```ruby
source = "a = if some_predicate then true else false end;" \
  "b = if some_other_predicate then true else false end;"

UnnecessaryConditionalRefactorer.new.refactor(source) do |refactoring|
  puts "About to replace '#{refactoring.original_code}' " \
       "at position #{refactoring.original_position} " \
       "with '#{refactoring.transformed_code}'"
end
 # About to replace 'if some_predicate then true else false end' at position 4..45 with 'some_predicate'
 # About to replace 'if some_other_predicate then true else false end' at position 51..98 with 'some_other_predicate'
 #  => "a = some_predicate;b = some_other_predicate;"
```

The `Metamorpher::Refactorer` module also defines a `refactor_file(path)` method, which can be used to apply refactoring to a file stored on disk:

```ruby
path = File.expand_path("refactorable.rb", "/Users/louis/code/mutiny")
 # => "/Users/louis/code/mutiny/refactorable.rb"

UnnecessaryConditionalRefactorer.new.refactor_file(path)
 # => ... (refactored code)

UnnecessaryConditionalRefactorer.new.refactor_file(path) do |refactoring|
  # works just like the block passed to refactor
end
 # => ... (refactored code)
```

You might prefer the `refactor_files(paths)` method, if you'd like to refactor several files at once:

```ruby
paths = Dir.glob(File.expand_path(File.join("**", "*.rb"), "/Users/louis/code/mutiny"))
 # => ["/Users/louis/code/mutiny/lib/mutiny.rb", ...]

 # Note that refactor_files returns a Hash rather than a String
UnnecessaryConditionalRefactorer.new.refactor_files(paths)
 # => { "/Users/louis/code/mutiny/lib/mutiny.rb" => (refactored code), ... }

 # Note that refactor_files yields for each file: its path, its new contents, and its refactoring sites
UnnecessaryConditionalRefactorer.new.refactor_files(path) do |path, new_contents, sites|
  puts "In #{path}:"

  sites.each do |site|
    puts "\tAbout to replace '#{refactoring.original_code}' " \
         "at position #{refactoring.original_position} " \
         "with '#{refactoring.transformed_code}'"
  end
end
 # In /Users/louis/code/mutiny/lib/mutiny.rb:
 #     About to replace 'if some_predicate then true else false end' at position 4..45 with 'some_predicate'
 # ...
 # => { "/Users/louis/code/mutiny/lib/mutiny.rb" => (refactored code), ... }
```

#### Refactoring programs written in other languages

By default, `Metamorpher::Refactorer` assumes that you wish to refactor Ruby programs, and will attempt to `require` the [parser](https://github.com/whitequark/parser) and [unparser](https://github.com/mbj/unparser) gems. If instead you wish to use a different Ruby parser / unparser or you wish to refactor a program written in a language other than Ruby, you should specify a different `driver`, as shown below. (A `Metamorpher::Driver` is responsible for transforming source code to metamorpher [terms](#building-terms), and vice-versa).

```ruby
class JavaRefactorer
  include Metamorpher::Refactorer

  def driver
    YourTool::MetamorpherDrivers::Java.new
  end

  def pattern
    ...
  end

  def replacement
    ...
  end
end
```

#### Examples

Below are a few examples of using metamorpher to perform refactorings on Ruby code.

##### Refactor Rails where(...).first

The following refactoring can be used to slightly tidy up code that uses ActiveRecord. Specifically, it refactors expressions of the form `User.where(...).first` to expressions of the form `User.find_by(...)`.

```ruby
require "metamorpher"

class RefactorWhereFirstToFindBy
  include Metamorpher::Refactorer
  include Metamorpher::Builders::Ruby

  def pattern
    builder.build("TYPE.where(PARAMS_).first")
  end

  def replacement
    builder.build("TYPE.find_by(PARAMS_)")
  end
end
```

This example was put together following a suggestion from [Sam Saffron](https://github.com/SamSaffron) and was applied to the discourse project. Complete code for the example (which includes refactorers for the impacted RSpec tests) is [here](https://github.com/mutiny/metamorpher/tree/master/examples/refactorings/rails/where_first).


##### Refactor Rails dynamic find_by

The following refactoring can be used to switch from ActiveRecord's dynamic `find_by` method to a version that uses a hash.

```ruby
require "metamorpher"

class RefactorWhereFirstToFindBy
  include Metamorpher::Refactorer
  include Metamorpher::Builders::Ruby

  def pattern
    builder
     .build("TYPE.METHOD(PARAMS_)")
     .ensuring("METHOD") { |f| f.name[/^find_by_/] }
  end

  def replacement
    builder
     .build("TYPE.find_by(HASH)")
     .deriving("HASH", "METHOD", "PARAMS") do |method, params|
       keys = attributes_from_dynamic_finder(method.name.to_s)
       values = params.map { |p| driver.unparse(p) }
       builder.build(create_hash_string(keys, values))
     end
  end

  private

  # Extracts an array of attributes from the name of a dynamic
  # finder, such as find_by_asset_id_and_object_path.
  def attributes_from_dynamic_finder(dynamic_finder)
    dynamic_finder["find_by_".length..-1].split("_and_")
  end

  # Builds a string representation of a hash from a set of keys
  # and a corresponding set of values
  def create_hash_string(keys, values)
    "{" + create_pairs_string(keys, values) + "}"
  end

  def create_pairs_string(keys, values)
    keys
     .zip(values)
     .map { |k, v| ":#{k} => #{v}" }
     .join(",")
  end
end
```

This example was put together following a suggestion from [Brian Morearty](https://github.com/bmorearty).

## Installation

Add these line to your application's Gemfile:

    gem 'metamorpher'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install metamorpher

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Acknowledgments

Thank-you to the authors of other projects and resources that have inspired metamorpher, including:

* Paul Klint's [tutorial on term rewriting](http://www.meta-environment.org/doc/books/extraction-transformation/term-rewriting/term-rewriting.html), which metamorpher is heavily based on.
* Jim Weirich's [Builder](https://github.com/jimweirich/builder) gem, which heavily influenced the design of `Metamorpher::Builders::AST::Builder`.
