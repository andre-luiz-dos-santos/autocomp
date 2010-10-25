" Vim global plugin for auto-completion
" Last Change: 2010 Oct 22
" Maintainer:	André Luiz dos Santos <andre.netvision.com.br@gmail.com>
" License: This file is placed in the public domain.
"{{{ Documentation
"
"   Installation
"
" Copy this file to the VIM plugin's directory.
" On Windows, this would be: ...\vimfiles\plugin\.
" On Linux: ~/.vim/plugin/.
"
"   Usage
"
" Press F5 on VIM instances where you want the auto-complete feature on, and
" wait for the auto-complete window to appear.
" You can choose another key with the following in your VIM rc file:
"  nmap <unique> <...> <Plug>AutocompStart
"
" Type the first letter of the word that you want. If the desired word appears
" on the auto-complete window, type its number. Otherwise, type the second
" letter of the word that you want. And so on.
" If you want to type the number and not auto-complete, type the number twice.
"
" Numbers above 10 are typed with the help of the Alt key. Example:
" 10 => Alt-0, 11 => Alt-1, etc.
"
"   TODO / Possibly needs fixing
"
" If this plug-in ever gains a second user, making it a bit more configurable
" might be necessary.
"
" I think that the following code may not be a good idea, since other plug-ins
" may also set it or depend on its default value:
"  setlocal updatetime=100
"
" Figure out how to invoke VIM's auto-complete functions manually.
" Making the code smarter about what possible auto-completions to present
" would be nice, too.
"
"}}}
"{{{ Initialization

if exists('loaded_autocomp')
	finish
endif
let loaded_autocomp = 1

let s:letters = '_'
let s:letters .= 'abcdefghijlmnopqrstuvxzywk'
let s:letters .= 'ABCDEFGHIJLMNOPQRSTUVXZYWK'

let s:programmerMode = 1

highlight AutoCompCommonPrefix term=inverse cterm=inverse gui=inverse

if !hasmapto('<Plug>AutocompStart')
	map <unique> <F5> <Plug>AutocompStart
endif
noremap <unique> <script> <Plug>AutocompStart <SID>Start
noremap <SID>Start :call <SID>StartPlugin()<CR>

" Everything below this point is script specific.

function s:StartPlugin()
	" Create the AutoComplete buffer if it doesn't exist yet.
	if !bufexists('AutoComplete')
		call s:CreateWindow()
		augroup autocomp
			autocmd!
			autocmd CursorMovedI * call <SID>CursorMovedIEvent()
			autocmd CursorHoldI * call <SID>CursorHoldIEvent()
			autocmd BufEnter * call <SID>BufEnterEvent()
		augroup END
		call s:BufEnterEvent()
	endif
endfunction

function s:CreateWindow()
	" Create the AutoComplete buffer.
	silent vertical leftabove 25new AutoComplete
	setlocal buftype=nofile noswapfile nonumber nowrap winfixwidth
	""nobuflisted
	call matchadd('AutoCompCommonPrefix', '\v^-\[.*\]-*$')
	" Go back to the previous window.
	wincmd p
endfunction

"}}}
"{{{ Word list

function s:CountWordsInLine(words, filter, line)
	for l:word in split(a:line, '[^' . s:letters . ']\+')
		" Pay attention to the pair of consecutive dots in the following line. It
		" means that the filter must be followed by at least two characters to
		" match.
		if match(l:word, '^' . a:filter . '..') >= 0
			let a:words[l:word] = get(a:words, l:word, 0) + 1
		endif
	endfor
endfunction

" Count how many times a word is used.
function s:CountWordsInBuffer(words, filter)
	let [l:curRow, l:totRows] = [line('.'), line('$')]
	for ln in getline(l:curRow < 41 ? 1 : l:curRow - 40, l:curRow + 40)
		call s:CountWordsInLine(a:words, a:filter, l:ln)
	endfor
	if len(a:words) < 20
		for ln in getline(l:curRow < 101 ? 1 : l:curRow - 100, l:curRow - 41)
			call s:CountWordsInLine(a:words, a:filter, l:ln)
		endfor
		for ln in getline(l:curRow + 41, l:curRow + 100)
			call s:CountWordsInLine(a:words, a:filter, l:ln)
		endfor
	endif
endfunction

function s:WordSortAlg(a, b)
	return a:b[1] - a:a[1]
endfunction

" Find the 20 most commonly used words.
" Result in b:words.
function s:UpdateWords(filter)
	let l:words = {}
	call s:CountWordsInBuffer(l:words, a:filter)
	" Create a sorted list of the 20 most commonly used words. {{{
	" items() ->
	" [ ['word', 3], ['wand', 5] ]
	" 1st sort() ->
	" [ ['wand', 5], ['word', 3] ]
	" map() ->
	" [ 'wand', 'word' ]
	" 2nd sort()
	" }}}
	let b:autocomp.words = sort(map(sort(items(l:words), 's:WordSortAlg')[:20-1], 'v:val[0]'))
endfunction

function s:FindCommonPrefixes()
	if s:programmerMode == 0
		" Find the most commonly used prefixes.
		let l:prefix = {} " dict value = use count.
		for w in b:autocomp.words
			for i in range(1, len(l:w) - len(b:autocomp.curWord))
				let l:key = strpart(l:w, len(b:autocomp.curWord), l:i)
				let l:prefix[l:key] = get(l:prefix, l:key, 0) + 1
			endfor
		endfor

		" Do not even consider prefixes not used this many times.
		let l:plist = reverse(sort(map(filter(items(l:prefix), 'v:val[1] >= 2'), 'v:val[0]')))
		if len(l:plist) == 0
			" A regular expression that will never match.
			return '\V\^\$'
		else
			return '\V\^' . b:autocomp.curWord . '\(' . join(l:plist, '\|') . '\)\(\.\+\)\$'
		endif
	elseif s:programmerMode == 1
		let l:prefixList = []
		let l:curWordSize = len(b:autocomp.curWord)

		for prefix in [ 'no', 'auto', 'end' ]
			if strpart(l:prefix, 0, l:curWordSize) == b:autocomp.curWord
				let l:prefixList += [strpart(l:prefix, len(b:autocomp.curWord))]
			endif
		endfor

		for word in b:autocomp.words
			for [pattern, offset] in [ ['\v._.', 1], ['\v[a-z][A-Z]', 1] ]
				let l:startAt = 0
				for dummy in range(4)
					let l:index = match(l:word, l:pattern, l:startAt)
					if l:index == -1
						break
					endif
					let l:index += l:offset
					let l:prefixList += [strpart(l:word, l:curWordSize, l:index - l:curWordSize)]
					let l:startAt = l:index + 1
				endfor
			endfor
		endfor

		return '\V\^' . b:autocomp.curWord . '\(' . join(l:prefixList, '\|') . '\)\(\.\+\)\$'
	endif
endfunction

function s:ClearWords()
	let b:autocomp.words = []
	""call s:UnmapAutoCompleteKeys()
	call s:WriteAutoCompleteBuffer()
endfunction

"}}}
"{{{ WriteAutoCompleteBuffer()

function s:WriteAutoCompleteBuffer()
	let l:wn = bufwinnr('AutoComplete')
	if l:wn != -1
		" Save buffer variables into local variables so they remain accessible
		" after the "wincmd" command below.
		let l:autocomp = b:autocomp
		let l:prefix_re = s:FindCommonPrefixes()
		" Save the current and the previous window numbers.
		" Restoration is done below. Necessary for the Project plug-in.
		" TODO: I feel like there must be an easier way to do this. :-)
		let [l:curWindow, l:prevWindow] = [winnr(), winnr('#')]
		" Move the cursor to the first window showing the AutoComplete buffer.
		" Makes the AutoComplete buffer the current buffer.
		execute l:wn . 'wincmd w'
		" Clear the AutoComplete buffer.
		" gg (go to beginning) "_ (don't save deleted text) dG (delete until the end of the buffer)
		normal gg"_dG
		" Show the list of words.
		let l:lines = []
		if empty(l:autocomp.words)
			let l:lines += ['---']
		else
			" Populate wordsByPrefix.
			let l:rootPrefix = l:autocomp.curWord
			let l:wordsByPrefix = {} " e => { 'e': [ 'xact', 'at' ], 'end': [ 'if', 'for' ] }
			for word in l:autocomp.words
				let l:ml = matchlist(l:word, l:prefix_re)
				if len(l:ml) > 0
					let [l:key, l:value] = [l:rootPrefix . l:ml[1], l:ml[2]]
				else
					let [l:key, l:value] = [l:rootPrefix, strpart(l:word, len(l:rootPrefix))]
				endif
				let l:wordsByPrefix[l:key] = get(l:wordsByPrefix, l:key, []) + [l:value]
			endfor
			if s:programmerMode == 0
				" Remove prefixes that have only one word.
				" Move removed words to the closest existing parent prefix.
				for prefix in reverse(sort(keys(l:wordsByPrefix)))
					if l:prefix != l:rootPrefix && len(l:wordsByPrefix[l:prefix]) == 1
						for j in range(len(l:prefix) - 1, 1, -1)
							let l:parentPrefix = strpart(l:prefix, 0, l:j)
							if has_key(l:wordsByPrefix, l:parentPrefix)
								let l:loneWord = strpart(l:prefix, len(l:parentPrefix)) . remove(l:wordsByPrefix, l:prefix)[0]
								let l:wordsByPrefix[l:parentPrefix] += [l:loneWord]
								break
							endif
						endfor
					endif
				endfor
			endif
			" Prepare lines for the auto-complete buffer.
			" Reorder b:autocomp.words.
			let l:newWordsList = []
			for prefix in sort(keys(l:wordsByPrefix))
				let l:lines += ['-[' . l:prefix . ']' . repeat('-', winwidth(0) - 3 - len(l:prefix))]
				for word in sort(l:wordsByPrefix[l:prefix])
					let l:lines += [len(l:newWordsList) . ' ' . l:word]
					let l:newWordsList += [l:prefix . l:word]
				endfor
			endfor
			let l:autocomp.words = l:newWordsList
		endif
		call setline(1, l:lines)
		" Restore windows.
		execute l:prevWindow . 'wincmd w'
		execute l:curWindow . 'wincmd w'
	endif
endfunction

"}}}
"{{{ Event Handlers

function s:CursorMovedIEvent()
	if exists('b:autocomp') && len(b:autocomp.words) > 0
		let [l:curY, l:curX] = getpos('.')[1:2]
		if b:autocomp.lastPos.x != l:curX || b:autocomp.lastPos.y != l:curY
			let [b:autocomp.lastPos.y, b:autocomp.lastPos.x] = getpos('.')[1:2]
			call s:ClearWords()
		endif
	endif
endfunction

function s:CursorHoldIEvent()
	if exists('b:autocomp')
		call s:LetterKeyPressed('')
		call s:WriteAutoCompleteBuffer()
		let [b:autocomp.lastPos.y, b:autocomp.lastPos.x] = getpos('.')[1:2]
	endif
endfunction

function s:BufEnterEvent()
	if bufname('%') == 'AutoComplete'
		return
	elseif !exists('b:autocomp')
		setlocal updatetime=100
		let b:autocomp = {'lastPos': {'x': -1, 'y': -1}, 'words': [], 'curWord': '', 'keysMapped': {'autoComplete': 0}, 'lastCompletion': {'key': '', 'line': '', 'x': -1, 'y': -1, 'addedChars': ''}}
	endif
	call s:WriteAutoCompleteBuffer()
endfunction

function s:LetterKeyPressed(key)
	" Don't do anything if the AutoComplete buffer is not shown.
	let l:wn = bufwinnr('AutoComplete')
	if l:wn == -1
		call s:UnmapAutoCompleteKeys()
		return
	endif

	" Get the current word. (The word under the cursor)
	let [l:curRow, l:curCol] = getpos('.')[1:2]
	let l:curLine = getline(l:curRow)
	let b:autocomp.curWord = matchstr(strpart(l:curLine, 0, l:curCol - 1), '[' . s:letters . ']*$')

	" Search for words that start with the current word.
	" If there is no current word, then do nothing.
	if b:autocomp.curWord == ''
		let b:autocomp.words = []
	else
		call s:UpdateWords(b:autocomp.curWord)
	endif

	if empty(b:autocomp.words)
		""call s:UnmapAutoCompleteKeys()
	else
		call s:MapAutoCompleteKeys()
	endif
endfunction

function s:AutoCompleteKeyPressed(key)
	let [l:curY, l:curX] = getpos('.')[1:2]
	if b:autocomp.lastCompletion.key == a:key && b:autocomp.lastCompletion.line == getline('.') && b:autocomp.lastCompletion.y == l:curY && b:autocomp.lastCompletion.x == l:curX
		" Undo auto-completion and type the number.
		call s:UnmapAutoCompleteKeys()
		let l:s = len(b:autocomp.lastCompletion.addedChars)
		execute 'normal a' . a:key
		execute 'normal ' . l:s . 'h' . l:s . 'x'
		let b:autocomp.lastCompletion.key = ''
	elseif a:key >= len(b:autocomp.words)
		" No word for the typed number, enter the number instead.
		call s:UnmapAutoCompleteKeys()
		if a:key < 10
			execute 'normal a' . a:key
		endif
		let b:autocomp.lastCompletion.key = ''
	else
		let l:chosenWord = b:autocomp.words[a:key]
		let l:newChars = strpart(l:chosenWord, len(b:autocomp.curWord))
		execute 'normal a' . l:newChars
"{{{ OUT: Uses getline() and setline().
""		let l:curLine = getline('.')
""		let [l:curRow, l:curCol] = getpos('.')[1:2]
""		let l:newChars = strpart(l:chosenWord, len(b:autocomp.curWord))
""		call setline(l:curRow, strpart(l:curLine, 0, l:curCol) . l:newChars . strpart(l:curLine, l:curCol))
""		call cursor(l:curRow, l:curCol + len(l:newChars))
"}}}
		let [b:autocomp.lastCompletion.key, b:autocomp.lastCompletion.line] = [a:key, getline('.')]
		let b:autocomp.lastCompletion.addedChars = l:newChars
		let [b:autocomp.lastCompletion.y, b:autocomp.lastCompletion.x] = getpos('.')[1:2]
	endif
endfunction

function s:EscapeKeyPressed()
	call s:ClearWords()
endfunction

"}}}
"{{{ Map and Unmap Keys

function s:MapAutoCompleteKeys()
	if !b:autocomp.keysMapped.autoComplete
		let b:autocomp.keysMapped.autoComplete = 1
		for i in range(0,9)
			execute 'inoremap <silent> <buffer> ' . i . ' <Esc>:call <SID>AutoCompleteKeyPressed(' . i . ')<CR>a'
			execute 'inoremap <silent> <buffer> <M-' . i . '> <Esc>:call <SID>AutoCompleteKeyPressed(' . (i + 10) . ')<CR>a'
		endfor
		inoremap <silent> <buffer> <Esc> <Esc>:call <SID>EscapeKeyPressed()<CR>
	endif
endfunction

function s:UnmapAutoCompleteKeys()
	if b:autocomp.keysMapped.autoComplete
		let b:autocomp.keysMapped.autoComplete = 0
		for i in range(0,9)
			execute 'iunmap <silent> <buffer> ' . i
			execute 'iunmap <silent> <buffer> <M-' . i . '>'
		endfor
		""iunmap <silent> <buffer> <Esc>
	endif
endfunction

"}}}
"{{{ Delete This!

"let b:autocomp.words = sort(map(sort(filter(items(b:wordCount), 'v:val[0] =~ "^' . a:filter . '.."'), 's:WordSortAlg')[:20-1], 'v:val[0]'))

"http://vimdoc.sourceforge.net/htmldoc/usr_27.html
" Patterns are almost like regular expressions, but they have some weird
" differences. For example: a+ should be written as a\+.
""after:	  \v	   \m	    \M	     \V		matches 
""		'magic' 'nomagic'
""	  $	   $	    $	     \$		matches end-of-line
""	  .	   .	    \.	     \.		matches any character
""	  *	   *	    \*	     \*		any number of the previous atom
""	  ()	   \(\)     \(\)     \(\)	grouping into an atom
""	  |	   \|	    \|	     \|		separating alternatives
""	  \a	   \a	    \a	     \a		alphabetic character
""	  \\	   \\	    \\	     \\		literal backslash
""	  \.	   \.	    .	     .		literal dot
""	  \{	   {	    {	     {		literal '{'
""	  a	   a	    a	     a		literal 'a'
""
"inoremap <F5> <C-R>=ListMonths()<CR>
"	func! ListMonths()
"	  call complete(col('.'), ['January', 'February', 'March',
"		\ 'April', 'May', 'June', 'July', 'August', 'September',
"		\ 'October', 'November', 'December'])
"	  return ''
"	endfunc

""b:name		variable local to a buffer
""	w:name		variable local to a window
""	g:name		global variable (also in a function)
""	v:name		variable predefined by Vi

"":if my_changedtick != b:changedtick
""		    :	let my_changedtick = b:changedtick
""		    :	call My_Update()
""		    :endif

"}}}
