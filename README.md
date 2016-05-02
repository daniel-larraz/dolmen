# Dolmen

A library providing flexible parsers for input languages.

## LICENSE

BSD2, see file LICENSE.

## Documentation

Online documentation for the dev version can be found at <http://gbury.github.io/dolmen>.
A tutorial is available at <https://github.com/Gbury/dolmen/tree/master/doc/tuto.md>.

## Current state

Currently the following parsers are working:

- dimacs
- smtlib
- tptp
- zf (zipperposition format)

The following parsers are either work in progress, or soon to be
work in progress:

- coq
- dedukti

## Architecture

This library provides functors to create parsers from a given
representation of terms. This allows users to have a parser that
directly outputs temrs in the desired form, without needing to
translate the parser output into the specific AST used in a project.

Parsers (actually, the functors which generates parsers) typically takes
three module arguments:

- A representation of locations in files. This is used for reporting
  parsing and lexing errors, but also to attach to each expression parsed
  its location.
- A representation of terms. The functions in this module are used by the
  parser to build the various types, terms and formulas corresponding
  to the grammar of the input language. All functions of this module
  typically takes as first (optional) argument a location (of the type
  defined by the previous argument) so that is is possible to have
  locations for expressions.
- A representation of top-level directives. Languages usually defines
  several top-level directives to more easily distinguish type definitions,
  axioms, lemma, theorems to prove, new assertions, or even sometimes direct
  commands for the solver (to set some options for instance). Again, the functions
  in this module usually have a first optional argument to set the location
  of the directives.

Some simple implementation of theses modules are provided in this library.
See the next section for more information.

## Examples

Examples of how to use the parsers can be found in src/main.ml . As mentionned
in the previous section, default implementation for the required functor arguments
are provided, and can be used.

For instance, the following code instantiates a parser for the smtlib language
and try to parse a file named "example.smt2" in the home of the current user:

```ocaml

open Dolmen
module P = Smtlib.Make(ParseLocation)(Term)(Statement)

let _ = P.parse_file "~/example.smt2"

```

## Future work

In addition to considering new languages, there are plans to improveme
incremental parsing error reporting, and possibly auto-detection of
input language on stdin.

