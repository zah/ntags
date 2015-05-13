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

import strutils, os, algorithm, sets

type
  State = enum Unknown, TypeDecl, VarDecl, Indented
  Token = enum tokProc, tokType, tokVar
  TraversalType = enum Recurse, Follow
  TraversalFlags = set[TraversalType]

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
    of '#':
      return -1
    else:
      return
  return -1

proc headToken(line: string, start: int): string =
  result = ""
  for i in start..len(line)-1:
    let ch = line[i]
    case ch
    of ' ', '\t', '#', ':': return
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
  shallow result
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

proc parseFile(path: string, lines: seq[string],
               startLine: int = 0, baseIndent: int = 0): (int, seq[string]) =
  var tags = newSeq[string]()
  var markIndent = -1
  var state = Unknown
  var lineNo = startLine
  while lineNo < len(lines):
    let line = lines[lineNo]
    lineNo += 1
    var ind = indent(line)
    if ind < 0:
      continue # skip empty line
    if ind < baseIndent:
      return (lineNo-1, tags)
    ind -= baseIndent

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
      let start = len(token) + baseIndent
      let names = idents(line, start)
      for tagEntry in genTagEntries(path, line, names, tokType):
        add(tags, tagEntry)

    if ind == 0:
      token = headToken(line, baseIndent)
      let eol = isEol(line, len(token)+baseIndent)
      case token
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
      of "when", "else":
        state = Indented
      else:
        discard
    else:
      case state
      of Unknown:
        discard
      of Indented:
        let (newLineNo, newTags) =
          parseFile(path, lines, lineNo-1, ind+baseIndent)
        add(tags, newTags)
        lineNo = newLineNo
        state = Unknown
      of TypeDecl:
        ifDeclaration:
          parseIdents(line, tokType)
      of VarDecl:
        ifDeclaration:
          parseIdents(line, tokVar)
  return (lineNo, tags)

proc fatal(msg: string) =
  quit("ntags: " & msg)

proc usage() =
  echo """ntags [options] path ...

  Generate tags file for Nim programs and modules.

  -f  --file PATH     specify tags file
  -R  --recurse       recurse through directories
      --no-recurse    do not recurse through directories
  -L  --follow        follow symbolic links
      --nofollow      do not follow symbolic links
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
  result = parseFile(path, lines)[1]
  
proc parseFileOrDir(path: string, travFlags: TraversalFlags): seq[string] =
  var
    idCache {.global.}: HashSet[(DeviceId, FileId)]
    idCacheInit {.global.}: bool
  if not idCacheInit:
    idCache = initSet[(DeviceId, FileId)]()
    idCacheInit = true
  var finfo: FileInfo
  try:
    finfo = getFileInfo(path)
  except:
    fatal("could not access file \"" & path & "\"")
  if idCache.containsOrIncl(finfo.id):
    return @[]
  case finfo.kind
  of pcFile:
    result = parseFile(path)
  of pcDir:
    if finfo.kind == pcDir or Follow in travFlags:
      result = @[]
      for kind, path2 in walkDir(path):
        case kind
        of pcFile:
          if path2.endsWith(".nim"):
            add(result, parseFile(path2))
        of pcDir:
          if Recurse in travFlags:
            add(result, parseFileOrDir(path2, travFlags))
        of pcLinkToFile, pcLinkToDir:
          if Follow in travFlags:
            try:
              case getFileInfo(path2).kind
              of pcFile:
                if path2.endsWith(".nim"):
                  add(result, parseFile(path2))
              of pcDir:
                add(result, parseFileOrDir(path2, travFlags))
              else:
                discard
            except:
              discard # ignore broken links
  else:
    # This cannot normally happen except as a result of
    # a race condition on the file system.
    fatal("changed symbolic link: " & path)
  
proc main() =
  var tagsFile = "tags"
  var tags = newSeq[string]()
  var travFlags: TraversalFlags
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
      incl travFlags, Recurse
    of "--no-recurse":
      excl travFlags, Recurse
    of "-L", "--follow":
      incl travFlags, Follow
    else:
      if arg[0] == '-':
        fatal("unrecognized option: " & arg)
      for tag in parseFileOrDir(arg, travFlags):
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
