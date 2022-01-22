vim9script
# Unit tests for Vim Language Server Protocol (LSP) client

syntax on
filetype on
filetype plugin on
filetype indent on

# Set the $LSP_PROFILE environment variable to profile the LSP plugin
var do_profile: bool = false
if exists('$LSP_PROFILE')
  do_profile = true
endif

if do_profile
  # profile the LSP plugin
  profile start lsp_profile.txt
  profile! file */lsp/*
endif

set rtp+=../
source ../plugin/lsp.vim
var lspServers = [{
      filetype: ['c', 'cpp'],
      path: '/usr/bin/clangd-12',
      args: ['--background-index', '--clang-tidy']
  }]
lsp#addServer(lspServers)

g:LSPTest = true

# The WaitFor*() functions are reused from the Vim test suite.
#
# Wait for up to five seconds for "assert" to return zero.  "assert" must be a
# (lambda) function containing one assert function.  Example:
#	call WaitForAssert({-> assert_equal("dead", job_status(job)})
#
# A second argument can be used to specify a different timeout in msec.
#
# Return zero for success, one for failure (like the assert function).
func WaitForAssert(assert, ...)
  let timeout = get(a:000, 0, 5000)
  if s:WaitForCommon(v:null, a:assert, timeout) < 0
    return 1
  endif
  return 0
endfunc

# Either "expr" or "assert" is not v:null
# Return the waiting time for success, -1 for failure.
func s:WaitForCommon(expr, assert, timeout)
  " using reltime() is more accurate, but not always available
  let slept = 0
  if exists('*reltimefloat')
    let start = reltime()
  endif

  while 1
    if type(a:expr) == v:t_func
      let success = a:expr()
    elseif type(a:assert) == v:t_func
      let success = a:assert() == 0
    else
      let success = eval(a:expr)
    endif
    if success
      return slept
    endif

    if slept >= a:timeout
      break
    endif
    if type(a:assert) == v:t_func
      " Remove the error added by the assert function.
      call remove(v:errors, -1)
    endif

    sleep 10m
    if exists('*reltimefloat')
      let slept = float2nr(reltimefloat(reltime(start)) * 1000)
    else
      let slept += 10
    endif
  endwhile

  return -1  " timed out
endfunc

# Test for formatting a file using LspFormat
def Test_LspFormat()
  :silent! edit Xtest.c
  setline(1, ['  int i;', '  int j;'])
  :redraw!
  :LspFormat
  :sleep 1
  assert_equal(['int i;', 'int j;'], getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, ['int f1(int i)', '{', 'int j = 10; return j;', '}'])
  :redraw!
  :LspFormat
  :sleep 500m
  assert_equal(['int f1(int i) {', '  int j = 10;', '  return j;', '}'],
							getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, ['', 'int     i;'])
  :redraw!
  :LspFormat
  :sleep 500m
  assert_equal(['', 'int i;'], getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, [' int i;'])
  :redraw!
  :LspFormat
  :sleep 500m
  assert_equal(['int i;'], getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, ['  int  i; '])
  :redraw!
  :LspFormat
  :sleep 500m
  assert_equal(['int i;'], getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, ['int  i;', '', '', ''])
  :redraw!
  :LspFormat
  :sleep 500m
  assert_equal(['int i;'], getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, ['int f1(){int x;int y;x=1;y=2;return x+y;}'])
  :redraw!
  :LspFormat
  :sleep 500m
  var expected: list<string> =<< trim END
    int f1() {
      int x;
      int y;
      x = 1;
      y = 2;
      return x + y;
    }
  END
  assert_equal(expected, getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, ['', '', '', ''])
  :redraw!
  :LspFormat
  :sleep 500m
  assert_equal([''], getline(1, '$'))

  deletebufline('', 1, '$')
  var lines: list<string> =<< trim END
    int f1() {
      int i, j;
        for (i = 1; i < 10; i++) { j++; }
        for (j = 1; j < 10; j++) { i++; }
    }
  END
  setline(1, lines)
  :redraw!
  :4LspFormat
  :sleep 500m
  expected =<< trim END
    int f1() {
      int i, j;
        for (i = 1; i < 10; i++) { j++; }
        for (j = 1; j < 10; j++) {
          i++;
        }
    }
  END
  assert_equal(expected, getline(1, '$'))
  bw!

  # empty file
  assert_equal('', execute('LspFormat'))

  # file without an LSP server
  edit a.b
  assert_equal(['Error: LSP server for "a.b" is not found'],
	       execute('LspFormat')->split("\n"))

  :%bw!
enddef

# Test for :LspShowReferences - showing all the references to a symbol in a
# file using LSP
def Test_LspShowReferences()
  :silent! edit Xtest.c
  var lines: list<string> =<< trim END
    int count;
    void redFunc()
    {
	int count, i;
	count = 10;
	i = count;
    }
    void blueFunc()
    {
	int count, j;
	count = 20;
	j = count;
    }
  END
  setline(1, lines)
  :redraw!
  cursor(5, 2)
  var bnr: number = bufnr()
  :LspShowReferences
  :sleep 1
  WaitForAssert(() => assert_equal('quickfix', getwinvar(winnr('$'), '&buftype')))
  var qfl: list<dict<any>> = getloclist(0)
  assert_equal(bnr, qfl[0].bufnr)
  assert_equal(3, qfl->len())
  assert_equal([4, 6], [qfl[0].lnum, qfl[0].col])
  assert_equal([5, 2], [qfl[1].lnum, qfl[1].col])
  assert_equal([6, 6], [qfl[2].lnum, qfl[2].col])
  :only
  cursor(1, 5)
  :LspShowReferences
  :sleep 500m
  WaitForAssert(() => assert_equal(1, getloclist(0)->len()))
  qfl = getloclist(0)
  assert_equal([1, 5], [qfl[0].lnum, qfl[0].col])
  bw!

  # empty file
  assert_equal('', execute('LspShowReferences'))

  # file without an LSP server
  edit a.b
  assert_equal(['Error: LSP server for "a.b" is not found'],
	       execute('LspShowReferences')->split("\n"))

  :%bw!
enddef

# Test for LSP diagnostics
def Test_LspDiag()
  :silent! edit Xtest.c
  var lines: list<string> =<< trim END
    void blueFunc()
    {
	int count, j:
	count = 20;
	j <= count;
	j = 10;
	MyFunc();
    }
  END
  setline(1, lines)
  :sleep 1
  var bnr: number = bufnr()
  :redraw!
  :LspDiagShow
  var qfl: list<dict<any>> = getloclist(0)
  assert_equal('quickfix', getwinvar(winnr('$'), '&buftype'))
  assert_equal(bnr, qfl[0].bufnr)
  assert_equal(3, qfl->len())
  assert_equal([3, 14, 'E'], [qfl[0].lnum, qfl[0].col, qfl[0].type])
  assert_equal([5, 2, 'W'], [qfl[1].lnum, qfl[1].col, qfl[1].type])
  assert_equal([7, 2, 'W'], [qfl[2].lnum, qfl[2].col, qfl[2].type])
  close
  normal gg
  var output = execute('LspDiagCurrent')->split("\n")
  assert_equal('No diagnostic messages found for current line', output[0])
  :LspDiagFirst
  assert_equal([3, 1], [line('.'), col('.')])
  output = execute('LspDiagCurrent')->split("\n")
  assert_equal("Expected ';' at end of declaration (fix available)", output[0])
  :LspDiagNext
  assert_equal([5, 1], [line('.'), col('.')])
  :LspDiagNext
  assert_equal([7, 1], [line('.'), col('.')])
  output = execute('LspDiagNext')->split("\n")
  assert_equal('Error: No more diagnostics found', output[0])
  :LspDiagPrev
  :LspDiagPrev
  :LspDiagPrev
  output = execute('LspDiagPrev')->split("\n")
  assert_equal('Error: No more diagnostics found', output[0])
  :%d
  setline(1, ['void blueFunc()', '{', '}'])
  sleep 500m
  output = execute('LspDiagShow')->split("\n")
  assert_match('No diagnostic messages found for', output[0])

  :%bw!
enddef

# Test for :LspCodeAction
def Test_LspCodeAction()
  silent! edit Xtest.c
  sleep 500m
  var lines: list<string> =<< trim END
    void testFunc()
    {
	int count;
	count == 20;
    }
  END
  setline(1, lines)
  sleep 500m
  cursor(4, 1)
  redraw!
  g:LSPTest_CodeActionChoice = 1
  :LspCodeAction
  sleep 500m
  WaitForAssert(() => assert_equal("\tcount = 20;", getline(4)))

  setline(4, "\tcount = 20:")
  cursor(4, 1)
  sleep 500m
  g:LSPTest_CodeActionChoice = 0
  :LspCodeAction
  sleep 500m
  WaitForAssert(() => assert_equal("\tcount = 20:", getline(4)))

  g:LSPTest_CodeActionChoice = 2
  cursor(4, 1)
  :LspCodeAction
  sleep 500m
  WaitForAssert(() => assert_equal("\tcount = 20:", getline(4)))

  g:LSPTest_CodeActionChoice = 1
  cursor(4, 1)
  :LspCodeAction
  sleep 500m
  WaitForAssert(() => assert_equal("\tcount = 20;", getline(4)))
  bw!

  # empty file
  assert_equal('', execute('LspCodeAction'))

  # file without an LSP server
  edit a.b
  assert_equal(['Error: LSP server for "a.b" is not found'],
	       execute('LspCodeAction')->split("\n"))

  :%bw!
enddef

# Test for :LspRename
def Test_LspRename()
  silent! edit Xtest.c
  sleep 1
  var lines: list<string> =<< trim END
    void F1(int count)
    {
	count = 20;

	++count;
    }

    void F2(int count)
    {
	count = 5;
    }
  END
  setline(1, lines)
  sleep 1
  cursor(1, 1)
  search('count')
  redraw!
  feedkeys(":LspRename\<CR>er\<CR>", "xt")
  sleep 1
  redraw!
  var expected: list<string> =<< trim END
    void F1(int counter)
    {
	counter = 20;

	++counter;
    }

    void F2(int count)
    {
	count = 5;
    }
  END
  WaitForAssert(() => assert_equal(expected, getline(1, '$')))
  bw!

  # empty file
  assert_equal('', execute('LspRename'))

  # file without an LSP server
  edit a.b
  assert_equal(['Error: LSP server for "a.b" is not found'],
	       execute('LspRename')->split("\n"))

  :%bw!
enddef

# Test for :LspSelectionRange
def Test_LspSelectionRange()
  silent! edit Xtest.c
  sleep 500m
  var lines: list<string> =<< trim END
    void F1(int count)
    {
        int i;
        for (i = 0; i < 10; i++) {
           count++;
        }
        count = 20;
    }
  END
  setline(1, lines)
  sleep 1
  # start a block-wise visual mode, LspSelectionRange should change this to
  # a characterwise visual mode.
  exe "normal! 1G\<C-V>G\"_y"
  cursor(2, 1)
  redraw!
  :LspSelectionRange
  sleep 1
  redraw!
  normal! y
  assert_equal('v', visualmode())
  assert_equal([2, 8], [line("'<"), line("'>")])
  # start a linewise visual mode, LspSelectionRange should change this to
  # a characterwise visual mode.
  exe "normal! 3GViB\"_y"
  cursor(4, 29)
  redraw!
  :LspSelectionRange
  sleep 1
  redraw!
  normal! y
  assert_equal('v', visualmode())
  assert_equal([4, 5, 6, 5], [line("'<"), col("'<"), line("'>"), col("'>")])
  bw!

  # empty file
  assert_equal('', execute('LspSelectionRange'))

  # file without an LSP server
  edit a.b
  assert_equal(['Error: LSP server for "a.b" is not found'],
	       execute('LspSelectionRange')->split("\n"))

  :%bw!
enddef

# Test for :LspGotoDefinition, :LspGotoDeclaration and :LspGotoImpl
def Test_LspGotoDefinition()
  silent! edit Xtest.cpp
  var lines: list<string> =<< trim END
    #include <iostream>
    using namespace std;

    class base {
	public:
	    virtual void print();
    };

    void base::print()
    {
    }

    class derived : public base {
	public:
	    void print() {}
    };

    void f1(void)
    {
	base *bp;
	derived d;
	bp = &d;

	bp->print();
    }
  END
  setline(1, lines)
  :sleep 1
  cursor(24, 6)
  :LspGotoDeclaration
  assert_equal([6, 19], [line('.'), col('.')])
  exe "normal! \<C-t>"
  assert_equal([24, 6], [line('.'), col('.')])
  :LspGotoDefinition
  assert_equal([9, 12], [line('.'), col('.')])
  exe "normal! \<C-t>"
  assert_equal([24, 6], [line('.'), col('.')])
  # FIXME: The following test is failing in Github CI
  # :LspGotoImpl
  # assert_equal([15, 11], [line('.'), col('.')])
  # exe "normal! \<C-t>"
  # assert_equal([24, 6], [line('.'), col('.')])

  # Error cases
  # FIXME: The following tests are failing in Github CI. Comment out for now.
  if 0
  :messages clear
  cursor(14, 5)
  :LspGotoDeclaration
  sleep 1
  var m = execute('messages')->split("\n")
  assert_equal('Error: declaration is not found', m[1])
  :messages clear
  :LspGotoDefinition
  sleep 1
  m = execute('messages')->split("\n")
  assert_equal('Error: definition is not found', m[1])
  :messages clear
  :LspGotoImpl
  sleep 1
  m = execute('messages')->split("\n")
  assert_equal('Error: implementation is not found', m[1])
  endif
  bw!

  # empty file
  assert_equal('', execute('LspGotoDefinition'))
  assert_equal('', execute('LspGotoDeclaration'))
  assert_equal('', execute('LspGotoImpl'))

  # file without an LSP server
  edit a.b
  assert_equal(['Error: LSP server for "a.b" is not found'],
	       execute('LspGotoDefinition')->split("\n"))
  assert_equal(['Error: LSP server for "a.b" is not found'],
	       execute('LspGotoDeclaration')->split("\n"))
  assert_equal(['Error: LSP server for "a.b" is not found'],
	       execute('LspGotoImpl')->split("\n"))

  :%bw!
enddef

# Test for :LspHighlight
def Test_LspHighlight()
  silent! edit Xtest.c
  var lines: list<string> =<< trim END
    void f1(int arg)
    {
      int i = arg;
      arg = 2;
    }
  END
  setline(1, lines)
  :sleep 1
  cursor(1, 13)
  :LspHighlight
  :sleep 1
  assert_equal([{'id': 0, 'col': 13, 'type_bufnr': 0, 'end': 1, 'type': 'LspTextRef', 'length': 3, 'start': 1}], prop_list(1))
  assert_equal([{'id': 0, 'col': 11, 'type_bufnr': 0, 'end': 1, 'type': 'LspReadRef', 'length': 3, 'start': 1}], prop_list(3))
  assert_equal([{'id': 0, 'col': 3, 'type_bufnr': 0, 'end': 1, 'type': 'LspWriteRef', 'length': 3, 'start': 1}], prop_list(4))
  :LspHighlightClear
  :sleep 1
  assert_equal([], prop_list(1))
  assert_equal([], prop_list(3))
  assert_equal([], prop_list(4))
  :%bw!
enddef

def LspRunTests()
  :set nomore
  :set debug=beep
  delete('results.txt')

  # Edit a dummy C file to start the LSP server
  :edit Xtest.c
  # Wait for the LSP server to become ready (max 10 seconds)
  var maxcount = 100
  while maxcount > 0 && !lsp#serverReady()
    :sleep 100m
    maxcount -= 1
  endwhile
  :%bw!

  # Get the list of test functions in this file and call them
  var fns: list<string> = execute('function /Test_')
		    ->split("\n")
		    ->map("v:val->substitute('^def <SNR>\\d\\+_', '', '')")
  for f in fns
    v:errors = []
    v:errmsg = ''
    try
      :%bw!
      exe f
    catch
      call add(v:errors, "Error: Test " .. f .. " failed with exception " .. v:exception .. " at " .. v:throwpoint)
    endtry
    if v:errmsg != ''
      call add(v:errors, "Error: Test " .. f .. " generated error " .. v:errmsg)
    endif
    if !v:errors->empty()
      writefile(v:errors, 'results.txt', 'a')
      writefile([f .. ': FAIL'], 'results.txt', 'a')
    else
      writefile([f .. ': pass'], 'results.txt', 'a')
    endif
  endfor
enddef

LspRunTests()
qall!

# vim: shiftwidth=2 softtabstop=2 noexpandtab