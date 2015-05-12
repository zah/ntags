# NTags

The `ntags` tool generates tags for Nim files, similar to how `ctags`
generates tags for C/C++ files.

# Installation

Use `nimble build` or `make opt` to build the release version, use
`make` to build the debug version.

# Usage

By default, `ntags` will scan all files and directories provided on the
command line and will write tags to the `tags` file in the current
directory. When scanning a directory, it will only parse files ending in
`.nim`.

The `-f <tagsfile>` option can be used to specify a different tags file
to output the tags to.

The `-R` or `--recurse` option can be used to tell `ntags` to recurse
through any directories it encounters. By default, it will only check
for `.nim` files at the top level of any directory encountered. This
option only affects directories listed after it on the command line.

The `--norecurse` option turns off directory recursion for all
subsequent directories.

Similarly, the `-L` and `--follow` options cause `ntags` to follow
symbolic links, while `--nofollow` suppresses the behavior. The
default is not to follow symbolic links.

# Limitations

The parser is still very simple. It can handle only top-level
declarations.

In particular, it does not handle:

* Declarations inside procedures.
* Enum members.
* Object fields.

It also does not handle inconsistent use of case/style. A future version
should scan the files for all possible uses of an identifier and
generate tags for all versions.
