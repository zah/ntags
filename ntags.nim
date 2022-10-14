# Copyright (c) 2015, Reimer Behrends <behrends@gmail.com>
# Distributed under the Boost Software License, Version 1.0
#
# Boost Software License - Version 1.0 - August 17th, 2003
#
# Permission is hereby granted, free of charge, to any person or organization
# obtaining a copy of the software and accompanying documentation covered by
# this license (the "Software") to use, reproduce, display, distribute,
# execute, and transmit the Software, and to prepare derivative works of the
# Software, and to permit third-parties to whom the Software is furnished to
# do so, all subject to the following:
#
# The copyright notices in the Software and this entire statement, including
# the above license grant, this restriction and the following disclaimer,
# must be included in all copies of the Software, in whole or in part, and
# all derivative works of the Software, unless such copies or derivative
# works are solely in the form of machine-executable object code generated by
# a source language processor.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
# SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
# FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

import strutils, os, algorithm, sets

type
  State = enum Unknown, TypeDecl, VarDecl, Indented, PostIndented
  Scope = enum Local, Global
  Token = enum tokProc, tokType, tokVar
  TagOption = enum Recurse, Follow, FixEol
  TagOptions = set[TagOption]

const
  tokenTypeName: array[Token, string] = ["f", "t", "v"]

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

proc printMarked(s: string, off: int) =
  echo s
  echo repeat(' ', off), "^"

proc idents(line: string, start: int): seq[(string, Scope)] =
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
      let ident = line[mark..pos-1]
      while pos < len(line) and line[pos] in {' ', '\t'}:
        pos += 1
      if pos < line.len and line[pos] == '*':
        pos += 1
        result.add((ident, Global))
      else:
        result.add((ident, Local))
    of '`':
      mark = pos
      pos += 1
      while pos < len(line) and line[pos] != '`':
        pos += 1
      if pos == len(line):
        return
      pos += 1
      let ident = line[mark..pos-1]
      while pos < len(line) and line[pos] in {' ', '\t'}:
        pos += 1
      if line[pos] == '*':
        pos += 1
        result.add((ident, Global))
      else:
        result.add((ident, Local))
    else:
      return

proc quoteSearch(line: string, options: TagOptions): string =
  result = "/^"
  for ch in line:
    if ch in {'/', '\\'}:
      add(result, '\\')
    add(result, ch)
  if FixEol in options:
    add(result, "\\r\\?")
  add(result, "$/")

proc genTagEntry(
  path: string,
  line: string,
  lineNo: int,
  name: string,
  scope: Scope,
  tokType: Token,
  options: TagOptions,
): string =
  result = ""
  shallow result
  add(result, name)
  add(result, '\t')
  add(result, path)
  add(result, '\t')
  add(result, quoteSearch(line, options))
  add(result, ";\"\t")
  add(result, tokenTypeName[tokType])
  add(result, '\t')
  if scope == Local:
    add(result, "file: ")
  add(result, "lineno:")
  add(result, $lineNo)
  add(result, "\n")

iterator genTagEntries(
  path: string,
  line: string,
  lineNo: int,
  tokens: seq[(string, Scope)],
  tokType: Token,
  options: TagOptions,
): string =
  for name, scope in tokens.items:
    yield genTagEntry(path, line, lineNo, name, scope, tokType, options)

proc parseFile(path: string, lines: seq[string], options: TagOptions,
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
          markIndent = -1

    var token: string

    template parseIdents(line: string, tokType: Token) =
      let start = len(token) + baseIndent
      let tokens = idents(line, start)
      for tagEntry in genTagEntries(path, line, lineNo, tokens, tokType, options):
        add(tags, tagEntry)

    if ind == 0:
      token = headToken(line, baseIndent)
      let eol = isEol(line, len(token)+baseIndent)
      case token
      of "func", "proc", "template", "macro", "iterator":
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
      of "when":
        state = Indented
      of "else", "elif":
        if state == PostIndented:
          state = Indented
        else:
          state = Unknown
      else:
        state = Unknown
    else:
      case state
      of Unknown:
        discard
      of PostIndented:
        state = Unknown
      of Indented:
        let (newLineNo, newTags) =
          parseFile(path, lines, options, lineNo-1, ind+baseIndent)
        add(tags, newTags)
        lineNo = newLineNo
        state = PostIndented
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
      --fix-eol       adjust for files with inconsistent end of line markers
"""
  quit(0)

proc parseFile(path: string, options: TagOptions): seq[string] =
  var lines: seq[string]
  try:
    var file = open(path, fmRead)
    lines = file.readAll.splitLines
    file.close()
  except:
    fatal("could not read file \"" & path & "\"")
  result = parseFile(path, lines, options)[1]
  
proc parseFileOrDir(path: string, options: TagOptions): seq[string] =
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
    result = parseFile(path, options)
  of pcDir:
    if finfo.kind == pcDir or Follow in options:
      result = @[]
      for kind, path2 in walkDir(path):
        case kind
        of pcFile:
          if path2.endsWith(".nim"):
            add(result, parseFile(path2, options))
        of pcDir:
          if Recurse in options:
            add(result, parseFileOrDir(path2, options))
        of pcLinkToFile, pcLinkToDir:
          if Follow in options:
            try:
              case getFileInfo(path2).kind
              of pcFile:
                if path2.endsWith(".nim"):
                  add(result, parseFile(path2, options))
              of pcDir:
                add(result, parseFileOrDir(path2, options))
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
  var options: TagOptions
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
      incl options, Recurse
    of "--no-recurse":
      excl options, Recurse
    of "-L", "--follow":
      incl options, Follow
    of "--fix-eol":
      incl options, FixEol
    else:
      if arg[0] == '-':
        fatal("unrecognized option: " & arg)
      for tag in parseFileOrDir(arg, options):
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
