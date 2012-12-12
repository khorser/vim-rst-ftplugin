" Vim filetype plugin
" Adds modeline for empty rst documents and implements functions for folding
" Language:	reStructuredText
" Last Change:	$HGLastChangedDate$
" Maintainer:	Sergey Khorev <sergey.khorev@gmail.com>

if v:version < 703 || !has('folding') || !has('syntax')
  finish
endif

if !exists('g:rst_debug')
  let g:rst_debug = 0
endif

if !exists('g:rsttitle_marks')
  let g:rsttitle_marks = '-=*+_~.#''`"^:;,!$%&()/<>?@\{|}]['
endif

if !exists('g:rstfolding_alltitles')
  let g:rstfolding_alltitles = split(g:rsttitle_marks, '\zs')
    \ + map(split(g:rsttitle_marks, '\zs'), 'v:val.v:val')
endif

if !exists('g:rstfolding_rxtitle')
  let g:rstfolding_rxtitle = '\V\^\['
    \ . substitute(g:rsttitle_marks, '\m]', '\\]', '') . ']\{2,\}\$'
endif

if !exists('g:rstfolding_rxprintable')
  let g:rstfolding_rxprintable = '\m\p'
endif

if !exists('g:rstfolding_rxempty')
  let g:rstfolding_rxempty = '\m^\s*$'
endif

if !exists('g:rstfolding_rxtext')
  let g:rstfolding_rxtext = '\m^\s*\(.\{-}\)\s*$'
endif

if !exists('g:rstsearch_order')
  let g:rstsearch_order = ['syntax', 'heuristics', 'user']
endif

function! s:IsEmpty(str)
  return empty(a:str) || a:str =~ g:rstfolding_rxempty
endfunction

function! s:GetTitle(lnum)
  let line = getline(a:lnum)
  let line1 = getline(a:lnum + 1)
  let line2 = getline(a:lnum + 2)
  if line =~ g:rstfolding_rxtitle && line1 =~ g:rstfolding_rxprintable &&
	\ line2 =~ g:rstfolding_rxtitle && line[0] == line2[0] &&
	\ s:IsEmpty(getline(a:lnum + 3))
    " overlined and underlined title
    return repeat(line[0], 2)
  elseif line =~ g:rstfolding_rxprintable &&
	\ line1 =~ g:rstfolding_rxtitle && s:IsEmpty(line2)
    " underlined title
    return line1[0]
  else
    return ''
  endif
endfunction

function! s:RstLevel(lnum)
  if !exists('b:rstfolding_titles')
    " array of decorations
    let b:rstfolding_titles = []
  endif
  if a:lnum == 1
    " not folding document title but saving its decoration nevertheless
    let title = s:GetTitle(a:lnum)
    if !empty(title)
      call add(b:rstfolding_titles, title)
    endif
    return 0
  endif

  let line = getline(a:lnum)
  if s:IsEmpty(line)
    return '='
  elseif !s:IsEmpty(getline(a:lnum - 1))
    " no blank lines before, no level changes
    return '='
  else
    let title = s:GetTitle(a:lnum)
    if empty(title)
      return '='
    endif

    let level = index(b:rstfolding_titles, title)
    if level > -1
      return '>'.level
    else
      call add(b:rstfolding_titles, title)
      return '>'.(len(b:rstfolding_titles) - 1)
    endif
  endif
endfunction

function! s:RstSectionTitle(lnum)
  return substitute(getline(a:lnum), g:rstfolding_rxtext, '\1', '')
endfunction

function! s:AddModeline()
  call append(line('$'), '.. vim' . ': set ft=rst:')
endfunction

function! s:RstFoldLevel()
  return s:RstLevel(v:lnum)
endfunction

function! s:RstLevelDebug(lnum)
  if !exists('b:rstfolding_debug')
    let b:rstfolding_debug = []
  endif
  let level = s:RstLevel(a:lnum)
  call add(b:rstfolding_debug, a:lnum.':'.level)
  return level
endfunction

function! s:RstFoldText()
  let title = s:GetTitle(v:foldstart)
  if empty(title)
    " just in case
    return foldtext()
  elseif len(title) == 1
    let text = s:RstSectionTitle(v:foldstart).' '.title[0]
  else
    let text = title[0].' '.s:RstSectionTitle(v:foldstart + 1).' '.title[0]
  endif
  return v:folddashes.' '.(v:foldend - v:foldstart + 1).' lines: '.text.' '
endfunction

" there is a title of level a:level at the next line
function! s:NextTitleEQ(lnum, level)
  if !s:IsEmpty(getline(a:lnum))
    return 0
  endif
  let title = s:GetTitle(a:lnum + 1)
  return !empty(title) && index(b:rstfolding_titles, title) == a:level
endfunction

" there is a title of level <= a:level at the next line
function! s:NextTitleLE(lnum, level)
  if !s:IsEmpty(getline(a:lnum))
    return 0
  endif
  let title = s:GetTitle(a:lnum + 1)
  return !empty(title) && index(b:rstfolding_titles, title) <= a:level
endfunction

" ]]
function! s:FindStartFwd(lnum, delta)
  let slevel = foldlevel(a:lnum)
  let curr = a:lnum + 1
  while foldlevel(curr) >= slevel && curr <= line('$')
    if s:NextTitleEQ(curr, slevel + a:delta)
      return curr + 1
    endif
    let curr += 1
  endwhile
  return 0
endfunction

" [[
function! s:FindStartBwd(lnum, delta, skipCurrStart)
  let slevel = foldlevel(a:lnum) - a:delta
  if a:skipCurrStart
    let curr = a:lnum - 1
  else
    let curr = a:lnum
  endif
  while foldlevel(curr) >= slevel && curr >= 1
    if s:NextTitleEQ(curr - 1, slevel)
      return curr
    endif
    let curr -= 1
  endwhile
  return 0
endfunction

" ][
function! s:FindEndFwd(lnum, delta, skipCurrEnd)
  let slevel = foldlevel(a:lnum) - a:delta
  if slevel < 0
    let slevel = 0
  endif
  let curr = a:lnum
  if !a:skipCurrEnd && foldlevel(curr + 1) < slevel
    return curr
  endif
  " figure out where we are
  if s:NextTitleEQ(a:lnum, slevel)
    if a:skipCurrEnd
      " we are at section end already and next section is at the same level
      let curr = a:lnum + 1
    else
      return curr
    endif
  endif
  " look for the required section
  while foldlevel(curr + 1) >= slevel && curr < line('$')
    if s:NextTitleLE(curr, slevel)
	return curr
    endif
    let curr += 1
  endwhile
  return (curr == a:lnum ? 0 : curr)
endfunction

" []
function! s:FindEndBwd(lnum, delta)
  let slevel = foldlevel(a:lnum) - a:delta
  let curr = a:lnum
  if s:IsEmpty(getline(a:lnum)) && !empty(s:GetTitle(a:lnum + 1))
    " we are at section end already, moving one line up
    let curr = a:lnum - 1
  endif
  while foldlevel(curr) >= slevel && curr >= 1
    if s:NextTitleLE(curr, slevel)
      return curr
    endif
    let curr -= 1
  endwhile
  return 0
endfunction

function! s:GotoNextSiblingStart(count)
  let found = s:FindStartFwd(line('.'), a:count)
  if found
    mark '
    exec found
  endif
endfunction

function! s:GotoPrevSiblingStart(count)
  let found = s:FindStartBwd(line('.'), a:count, 1)
  if found
    mark '
    exec found
  endif
endfunction

function! s:GotoNextSiblingEnd(count)
  let found = s:FindEndFwd(line('.'), a:count, 1)
  if found
    mark '
    exec found
  endif
endfunction

function! s:GotoPrevSiblingEnd(count)
  let found = s:FindEndBwd(line('.'), a:count)
  if found
    mark '
    exec found
  endif
endfunction

function! s:WriteTitle(pos, adornment)
  let title = input('Enter section title: ', '')
  if !empty(title) && a:pos > 0
    let pos = a:pos
    if len(a:adornment) > 1
      call append(pos, repeat(a:adornment[0], len(title)))
      let pos += 1
    endif
    call append(pos, title)
    let pos += 1
    call append(pos, repeat(a:adornment[0], len(title)))
    let pos += 1
    call append(pos, '')
    let pos += 1
    call append(pos, '')
    let pos += 1
    call append(pos, '')
    call cursor(pos, 1)
    normal zv
  endif
endfunction

function! s:AddSibling(pos)
  call s:WriteTitle(a:pos, b:rstfolding_titles[foldlevel(line('.'))])
endfunction

function! s:AddSiblingAbove()
  call s:AddSibling(s:FindStartBwd(line('.'), 0, 0) - 1)
endfunction

function! s:AddSiblingBelow()
  call s:AddSibling(s:FindEndFwd(line('.'), 0, 0))
endfunction

function! s:WarningMsg(msg)
  echohl WarningMsg | echo a:msg | echohl None
endfunction

function! s:InputTitle(prompt)
  let a = input('Enter adorment style for '.a:prompt.': ', '')
  if empty(a) || len(a) > 2 || (len(a) == 2 && a[0] != a[1]) ||
	\ index(b:rstfolding_titles, a) != -1 ||
	\ index(g:rstfolding_alltitles, a) == -1
    call s:WarningMsg('Invalid adornment style')
    return ""
  else
    return a
  endif
endfunction

function! s:AddChild(pos)
  let slevel = foldlevel(line('.')) + 1
  if slevel >= len(b:rstfolding_titles)
    let a = s:InputTitle('a child')
  else
    let a = b:rstfolding_titles[slevel]
  endif
  call s:WriteTitle(a:pos, a)
endfunction

function! s:AddAsFirstChild()
  let pos = s:FindStartFwd(line('.'), 1)
  if !pos
    call s:AddAsLastChild()
  else
    call s:AddChild(pos - 1)
    " update folds
    normal zx
  endif
endfunction

function! s:AddAsLastChild()
  call s:AddChild(s:FindEndFwd(line('.'), 0, 0))
endfunction

function! s:UpdateTitles(start, end, shift)
  " adjustments which might be cause because of replacement
  " over + underlined titles with underlined etc
  let adj = 0
  let curr = a:start
  while curr <= a:end + adj
    if s:IsEmpty(getline(curr - 1))
      let title = s:GetTitle(curr)
      if !empty(title)
	let new = b:rstfolding_titles[index(b:rstfolding_titles, title) + a:shift]
	if len(title) == 1
	  let newdeco = repeat(new[0], len(getline(curr + 1)))
	  if len(new) == 1
	    call setline(curr + 1, newdeco)
	  else
	    call append(curr - 1, newdeco)
	    call setline(curr + 2, newdeco)
	  endif
	else
	  let newdeco = repeat(new[0], len(getline(curr)))
	  if len(new) == 1
	    exec curr.'delete _'
	    call setline(curr + 1, newdeco)
	  else
	    call setline(curr, newdeco)
	    call setline(curr + 2, newdeco)
	  endif
	endif
	let delta = len(new) - len(title)
	let curr += 1 + delta
	let adj += delta
      endif
    endif
    let curr += 1
  endwhile
  normal zx
endfunction

function! s:Promote()
  let l = line('.')
  if foldlevel(l) < 2
    call s:WarningMsg('Cannot promote top-level sections')
    return
  endif
  let start = s:FindStartBwd(l, 0, 0)
  let end = s:FindEndFwd(l, 0, 0)
  call s:UpdateTitles(start, end, -1)
endfunction

function! s:Demote()
  let l = line('.')
  if foldlevel(l) == 0
    call s:WarningMsg('Cannot demote top-level sections')
    return
  endif
  let upper = s:FindStartBwd(l, 0, 1)
  if !upper
    call s:WarningMsg('Cannot find upper sibling')
    return
  endif
  let start = s:FindStartBwd(l, 0, 0)
  let end = s:FindEndFwd(l, 0, 0)
  let curr = start
  let max = foldlevel(l)
  while curr <= end
    if foldlevel(curr) > max
      let max = foldlevel(curr)
    endif
    let curr += 1
  endwhile
  if max + 1 >= len(b:rstfolding_titles)
    let a = s:InputTitle('the lowest level')
    if empty(a)
      return
    else
      call add(b:rstfolding_titles, a)
      call s:UpdateTitles(start, end, +1)
    endif
  endif
endfunction

function! s:RstReset()
  let b:rstfolding_titles = []
  normal zx
endfunction

nmap <silent> <buffer> ]] :<C-U>call <SID>GotoNextSiblingStart(v:count)<CR>
nmap <silent> <buffer> [[ :<C-U>call <SID>GotoPrevSiblingStart(v:count)<CR>
nmap <silent> <buffer> ][ :<C-U>call <SID>GotoNextSiblingEnd(v:count)<CR>
nmap <silent> <buffer> [] :<C-U>call <SID>GotoPrevSiblingEnd(v:count)<CR>

nmap <silent> <buffer> <localleader>O :call <SID>AddSiblingAbove()<CR>
nmap <silent> <buffer> <localleader>o :call <SID>AddSiblingBelow()<CR>
nmap <silent> <buffer> <localleader>A :call <SID>AddAsFirstChild()<CR>
nmap <silent> <buffer> <localleader>a :call <SID>AddAsLastChild()<CR>

nmap <silent> <buffer> <localleader>< :call <SID>Promote()<CR>
nmap <silent> <buffer> <localleader>> :call <SID>Demote()<CR>

command! -buffer RstReset call <SID>RstReset()

" TODO
"  - mapping to adust the length of over- and under-line of a title
"  - change decoration style
"
"  operators (:help :map-operator)

if line('$') == 1 && getline(1) == ''
  call s:AddModeline()
endif

set foldexpr=<SID>RstFoldLevel() foldtext=<SID>RstFoldText() foldmethod=expr

if exists('b:rst_fold_level')
  let &foldlevel = b:rst_fold_level
elseif exists('g:rst_fold_level')
  let &foldlevel = g:rst_fold_level
endif

if !exists('g:rstnav_rx')
" the order is important, name is for reference only
let g:rstnav_rx = [
      \	{ 'name': 'cite/footnote',
      \	  'syntax' : ['rstCitationReference', 'rstFootnoteReference'],
      \	  'ref' : '\m^\zs\[[^\]]\+]\ze_$',
      \	  'target' : '\m\c^\s*\.\.\s\+\V\1\m\s*\zs'},
      \ { 'name': 'anonymous links',
      \	  'syntax' : ['rstHyperlinkReference', 'rstInterpretedTextOrHyperlinkReference'],
      \	  'ref' : '\m^\%(\w\+\|`\_p\+`\)\zs__\ze$',
      \	  'target' : '\m\c^\s*\.\.\s*__:\s\+\|^\s*__\s\+'},
      \ { 'name': 'reference to sections, explicit targets, and internal targets',
      \	  'syntax' : ['rstHyperlinkReference', 'rstInterpretedTextOrHyperlinkReference'],
      \	  'ref' : '\m^\%(\zs\S*[0-9A-Za-z]\ze\|`\zs\_p\+\ze`\)_$',
      \	  'target' : '\m\c^\s*\zs\V\1\m\s*$\|^\s*\.\.\s*_\V\1\m:\s\+\zs\|_`\zs\V\1\m`'},
      \ { 'name': 'substitution',
      \	  'syntax' : ['rstSubstitutionReference'],
      \	  'ref' : '\m^|\zs\p\+\ze|_\?$',
      \	  'target' : '\m^\c\s*\.\.\s*|\V\1\m|\s*\zs\|^\s*\.\.\s*_\V\1\m\s*:\s\+\zs'},
      \ { 'name': 'substitution with anonymous reference',
      \	  'syntax' : ['rstSubstitutionReference'],
      \	  'ref' : '\m^|\zs\p\+\ze|__$',
      \	  'target' : '\m\c^\s*\.\.\s*|\V\1\m|\s*\zs\|^\s*__\s\+\zs'}
      \ ]
endif

" remap other keys to implement jumping to targets (+add to tagstack)?
" use syntax highlighting to improve search for sections?
nmap <silent> <buffer> <localleader><C-]> :call <SID>RstFollowLink()<cr>
nmap <silent> <buffer> <localleader>] :call <SID>RstNextLink()<cr>

let s:last_pattern = ''

" extract reference text using syntax highlighting
function! s:RstExtractRef()
  let line = line('.')
  let col = col('.')
  let syn = synID(line, col, 1)
  " check visual selection?
  " find the start and the end
  let c1 = col('.') - 1
  while c1 > 0 && synID(line, c1, 1) == syn
    let c1 -= 1
  endwhile
  let c2 = col('.') + 1
  let en = col('$')
  while c2 < en && synID(line, c2, 1) == syn
    let c2 += 1
  endwhile
  let str = s:Trim(getline(line)[c1 : c2-2])

  " checking next line
  let line2 = line + 1
  let str2 = getline(line2)
  if c2 == en && line < line('$')
	\ && synID(line2, 1, 1) == syn
    let en = len(str2)
    let c = 1
    while c < en && synID(line2, c, 1) == syn
      let c += 1
    endwhile
    let str .= '\s\+' . s:Trim(str2[ : c-2])
  endif

  " checking prev line
  let line2 = line - 1
  let str2 = getline(line2)
  if c1 == 0 && line > 1
	\  && synID(line2, len(str2), 1) == syn
    let c = len(str2)
    while c > 0 && synID(line2, c, 1) == syn
      let c -= 1
    endwhile
    let c1 = 0
    let en = len(str)
    let str = s:Trim(str2[c : ]) . '\s\+' . str
  endif
  return [str, syn]
endfunction

function! s:Trim(str)
  return substitute(a:str, '\m^\s*\(.\{-}\)\s*$', '\1', '')
endfunction

" try to extract reference without using syntax highlighting
function! s:RstGuessRef()
  let line = line('.')
  let col = col('.')

  let [l2, c2, suf] = searchpos('\m\%(\(__\)\|\(_\)\)\>', 'cnWp', line+2)
  let [l2_, c2_] = searchpos('\m|', 'cnW', line+2)
  if l2 && (!l2_ || l2 < l2_ || l2 == l2_ && c2 <= c2_)
    return s:Underlined(l2, c2, suf)
  elseif l2_
    return s:Substitution(l2_, c2_)
  else
    return '' " not a reference
  endif
endfunction

function! s:Underlined(l2, c2, suf)
  if a:c2 > 1
    let str = getline(a:l2)
    let delim = str[a:c2-2]
  elseif a:l2 > 1
    let str = getline(a:l2-1)
    let delim = str[-1:]
  else
    let delim = ''
  endif
  let l1 = 0
  let c1 = 0
  if !empty(delim) && stridx('`|]', delim) > -1
    " try to find a pair for our delimiter
    if delim == ']'
      let delim = '['
    endif
    let [l1, c1] = searchpos('\m'.delim, 'bcnW', a:l2-2)
  endif
  if !l1
    return expand('<cword>') " no delimiters found
  endif
  let text = getline(l1, a:l2)
  if l1 == a:l2
    let text[0] = strpart(text[0], c1-1, a:c2 + (4-a:suf) - c1)
  else
    let text[0] = strpart(text[0], c1-1)
    let text[-1] = strpart(text[-1], 0, a:c2 + (4-a:suf))
  endif
  call map(text, 's:Trim(v:val)')
  return join(text, '\s\+')
endfunction

function! s:Substitution(l2, c2)
  let [l1, c1] = searchpos('\m|', 'bcnW', a:l2-1)
  if !l1
    return ''
  endif
  let text = getline(l1, a:l2)
  if l1 == a:l2
    let text[0] = strpart(text[0], c1-1, a:c2-c1+1)
  else
    let text[0] = strpart(text[0], c1-1)
    let text[-1] = strpart(text[-1], 0, a:c2)
  endif
  call map(text, 's:Trim(v:val)')
  return join(text, '\s\+')
endfunction!

function! s:Debug(msg1, msg2)
  if g:rst_debug
    echom a:msg1 a:msg2
  endif
endfunction

function! s:RstFollowLink()
  for method in g:rstsearch_order
    if method == 'syntax'
      if s:Syntax()
	return
      endif
    elseif method == 'heuristics'
      if s:Guess()
	return
      endif
    elseif method == 'user' && exists('*g:RstUserSearch')
      call s:Debug ('Using user-supplied search', method)
      if g:RstUserSearch()
	return
      endif
    endif
  endfor
  call s:WarningMsg('Pattern not found')
endfunction

function! s:Syntax()
  let [str, syn] = s:RstExtractRef()
  call s:Debug ('Using syntax to look for', str)
  for descr in g:rstnav_rx
    call s:Debug('trying rx', descr.name)
    if index(descr.syntax, synIDattr(syn, 'name')) > -1
      call s:Debug('matching {'.str.'}', 'against {'.descr.ref.'}')
      if s:RstFindTarget(str, descr)
	return 1
      endif
    endif
  endfor
endfunction

function! s:Guess()
  let str = s:RstGuessRef()
  call s:Debug ('Using guessing to look for', str)
  for descr in g:rstnav_rx
    call s:Debug('trying rx', descr.name)
    call s:Debug('matching {'.str.'}', 'against {'.descr.ref.'}')
    if s:RstFindTarget(str, descr)
      return 1
    endif
  endfor
endfunction

function! s:RstFindTarget(str, descr)
  let pattern = matchstr(a:str, a:descr.ref)
  call s:Debug('pattern:', pattern)
  if !empty(pattern)
    let target = a:descr.target
    " need to be careful with metacharacters so not using
    " substitute() that always handles patterns as if 'magic' is set
    while (1)
      let i = stridx(target, '\1')
      if i > 0
	let target = target[:i-1] . pattern . target[i+2:]
      else
	break
      endif
    endwhile
    call s:Debug('looking for', target)
    let pos = searchpos(target, 'ws')
    if pos != [0, 0]
      let s:last_pattern = target
      return 1
    endif
  endif
  return 0
endfunction

function! s:RstNextLink()
  if !empty(s:last_pattern)
    call searchpos(s:last_pattern, 'ws')
  endif
endfunction

finish

Vimball contents:
doc/ft_rst.txt
after/ftplugin/rst.vim
" vim: set ts=8 sts=2 sw=2:
