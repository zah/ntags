# Copyright (c) 2015, Reimer Behrends <behrends@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import strutils, os, algorithm

type
  State = enum Unknown, TypeDecl, VarDecl
  Token = enum tokProc, tokType, tokVar

proc isEol(line: string, at: int): bool =
  var pos = at
  while pos < len(line):
    case line[pos]
    of '#': return true
    of ' ', '\t': discard
    else: return false
    pos += 1
  return true

proc indent(line: string): int =
  for ch in line:
    case ch
    of ' ': result += 1
    else:
      return
  result = 0

proc headToken(line: string): string =
  result = ""
  for ch in line:
    case ch
    of ' ', '\t', '#': return
    else: add(result, ch)

proc idents(line: string, start: int): seq[string] =
  result = @[]
  var pos = start
  var mark: int
  while pos < len(line):
    case line[pos]:
    of ' ', '\t', '*', ',':
      pos += 1
    of 'A'..'Z', 'a'..'z':
      mark = pos
      const identChars = {'a'..'z', 'A'..'Z', '0'..'9', '_'}
      while pos < len(line) and line[pos] in identChars:
        pos += 1
      result.add(line[mark..pos-1])
    of '`':
      mark = pos
      pos += 1
      while pos < len(line) and line[pos] != '`':
        pos += 1
      if pos == len(line):
        return
      result.add(line[mark..pos])
      pos += 1
    else:
      return

proc quoteSearch(line: string): string =
  result = "/^"
  for ch in line:
    if ch in {'/', '^', '$', '\\'}:
      add(result, '\\')
    add(result, ch)
  add(result, "$/")

proc genTagEntry(path, line: string, name: string, tokType: Token): string =
  result = ""
  add(result, name)
  add(result, '\t')
  add(result, path)
  add(result, '\t')
  add(result, quoteSearch(line))
  add(result, "\n")

iterator genTagEntries(path, line: string,
                       names: seq[string], tokType: Token): string =
  for name in names:
    yield genTagEntry(path, line, name, tokType)

proc parseFile(path: string, lines: seq[string]): seq[string] =
  result = @[]
  var markIndent = -1
  var state = Unknown
  for line in lines:
    let ind = indent(line)

    template ifDeclaration(body: untyped) =
      if not isEol(line, 0):
        if markIndent < 0:
          markIndent = ind
        if markIndent == ind:
          body
        if ind < markIndent:
          state = Unknown

    var token: string

    template parseIdents(line: string, tokType: Token) =
      let start = len(token)
      let names = idents(line, start)
      for tagEntry in genTagEntries(path, line, names, tokType):
        add(result, tagEntry)

    if ind == 0:
      token = headToken(line)
      let eol = isEol(line, len(token))
      case headToken(line)
      of "proc", "template", "macro", "iterator":
        parseIdents(line, tokProc)
        state = Unknown
      of "type":
        if not eol:
          parseIdents(line, tokType)
          state = Unknown
        else:
          state = TypeDecl
      of "let", "var", "const":
        if not eol:
          parseIdents(line, tokVar)
          state = Unknown
        else:
          state = VarDecl
      else:
        discard
    else:
      token = nil
      case state
      of Unknown:
        discard
      of TypeDecl:
        ifDeclaration:
          parseIdents(line, tokType)
      of VarDecl:
        ifDeclaration:
          parseIdents(line, tokVar)

proc fatal(msg: string) =
  quit("ntags: " & msg)

proc usage() =
  echo """ntags [options] path ...

  Generate tags file for Nim programs and modules.

  -f  --file PATH    specify tags file
  -R  --recurse      recurse through directories
      --no-recurse   do not recurse through directories
"""
  quit(0)

proc parseFile(path: string): seq[string] =
  var lines: seq[string]
  try:
    var file = open(path, fmRead)
    lines = file.readAll.splitLines
    file.close()
  except:
    fatal("could not read file \"" & path & "\"")
  result = parseFile(path, lines)
  
proc parseFileOrDir(path: string, recurse: bool): seq[string] =
  var finfo: FileInfo
  try:
    finfo = getFileInfo(path)
  except:
    fatal("could not access file \"" & path & "\"")
  case finfo.kind
  of pcFile, pcLinkToFile:
    result = parseFile(path)
  of pcDir, pcLinkToDir:
    result = @[]
    for kind, path2 in walkDir(path):
      case kind
      of pcFile, pcLinkToFile:
        if path2.endsWith(".nim"):
          add(result, parseFile(path2))
      of pcDir, pcLinkToDir:
        if recurse:
          add(result, parseFileOrDir(path2, recurse))
  
proc main() =
  var tagsFile = "tags"
  var tags = newSeq[string]()
  var recurse = false
  var i = 1
  let nargs = paramCount()
  if nargs == 0 or nargs == 1 and paramStr(1) in ["-h", "--help"]:
    usage()
  while i <= nargs:
    let arg = paramStr(i)
    case arg
    of "-f", "--file":
      if i == nargs:
        fatal("missing argument to -f option")
      i += 1
      tagsFile = paramStr(i)
    of "-R", "--recurse":
      recurse = true
    of "--no-recurse":
      recurse = false
    else:
      if arg[0] == '-':
        fatal("unrecognized option: " & arg)
      for tag in parseFileOrDir(arg, recurse):
        add(tags, tag)
    i += 1
  tags.sort(cmp)
  try:
    var file = open(tagsFile, fmWrite)
    file.write("!_TAG_FILE_FORMAT\t1\n")
    file.write("!_TAG_FILE_SORTED\t1\n")
    file.write(tags.join)
    file.close
  except:
    fatal("could not write tags file")

main()
