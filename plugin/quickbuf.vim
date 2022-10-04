" *QuickBuf* Creates a prompt to allow for quick
"   \ and non-intrusive buffer switching
" Author:      Jaspreet Panesar <jaspreetpanesar>
" Version:     2.0
" Last Change: 2020 Apr 12
" Licence:     This file is placed in the public domain.

if v:version < 700 || &compatible || exists("g:loaded_quickbuf")
    " finish
endif
let g:loaded_quickbuf = 1

"--------------------------------------------------
"   *** CONSTANTS ***
"--------------------------------------------------
" selection vals fallback
let s:c_mselvals = '1234abcdef'
let s:c_mselmax = 10

let s:enum_selectionmode = {
    \ 'filepath' : 0,
    \ 'aliases'  : 1,
    \ 'arglist'  : 2,
    \ 'bufnr'    : 3,
    \ 'noname'   : 4,
    \ }

"--------------------------------------------------
"   *** CONFIGURATION ***
"--------------------------------------------------
" TODO convert to global configurable variables
let s:switch_windowtoggle = 0
let s:switch_multiselect = 0
let s:msw_selection_vals = s:c_mselvals
let s:custom_commandname = "QuickBuffer"

"--------------------------------------------------
"   *** GLOBALS ***
"--------------------------------------------------
let s:aliases = {}
let s:buffercache = []

"--------------------------------------------------
"   *** Buffer Context Items ***
"--------------------------------------------------
let s:bufitem = {
\ 'name': '',
\ 'context': '',
\ 'relpath': '',
\ 'fullpath': '',
\ 'bufnr': '',
\ 'is_modified': 0,
\ 'is_current': 0,
\ 'is_alternate': 0,
\ 'is_noname': 0,
\ }

" TODO this should only be happening once per buffer lifetime
function! s:bufitem.new(binfo) abort
    let item = copy(self)
    call item._gen(a:binfo)
    return item
endfunction

" renegrate minimal amount of data
" ie. context, and flags
" will be run everytime before item is shown
function! s:bufitem.upd(binfo) abort
    " update flags is_current, is_alternate, is_modified
    " update context
endfunction

" regenerate all data
function! s:bufitem.regen() abort
    let binfo = getbufinfo(self.bufnr)
    call self._gen(binfo)
endfunction

function! s:bufitem._gen(binfo) abort
    let self.bufnr = a:binfo.bufnr
    let self.is_current = (bufnr() == self.bufnr)
    let self.is_alternate = (bufnr('#') == self.bufnr)
    let self.is_modified = a:binfo.changed

    let path = a:binfo.name
    if empty(path)
        let self.is_noname = 1
        let self.name = '#'.self.bufnr
   else
        let self.fullpath = path
        let self.relpath = fnamemodify(path, ':.')
        let self.name = fnamemodify(path, ':t')
        let self.context = fnamemodify(path, ':h')
    endif

endfunction

function! s:bufitem.tostring() abort
    return self.name . ' (' . self.context . ')'
endfunction

" TODO cache this list with autocmds ?
function! s:bcache_load() abort
    let items = []
    for buf in getbufinfo({'buflisted':1})
        call add(items, s:bufitem.new(buf))
    endfor
    let s:buffercache = items
endfunction

"--------------------------------------------------
"   *** Expression Engine ***
"--------------------------------------------------
let s:Expression = {}

function! s:Expression.reset() abort
    let self.input = ''
    let self.inputchars = ''
    let self.inputflags = ['', '']
    let self.data_prefill = ''
    let self.data_results = []
    let self.data_exitrequested = 0
    let self.data_selectionmode = 0
endfunction

" needed to setup object properties
call s:Expression.reset()

function! s:Expression._build(expr) abort
    let self.input = a:expr

    if empty(a:expr)
        return
    endif

    " check for quoted expressions first
    " ie. anything inside start/end quotes will not be seen as a flag
    "   eg. ^"^~/home$"? where 1st ^ is a flag, but 2nd is not
    " (this will match on the very last quote in the expression so quotes
    "  chars can be quoted)
    let pos = matchstrpos(a:expr, '"\zs.*\ze"')

    " otherwise use best guess filepath matching as before. this match
    " limits filename character scope to alphanumeric, some filepath
    " chars and standard path characters
    if pos[1] == -1 
        let pos = matchstrpos(a:expr, '[a-zA-Z0-9\._\-%\/:~]\+')
    endif

    let self.inputchars = pos[0]
    if pos[1] > -1
        let self.inputflags[0] = pos[1] > 0 ? a:expr[:(pos[1]-1)] : ''
        let self.inputflags[1] = a:expr[pos[2]:]
    else
        " when no characters were found (ie. prompt empty)
        let self.inputflags = [a:expr, '']
    endif

endfunction

function! s:Expression._complete(value) abort
    " need to use [A]rgLead (not Cmd[L]ine) for command-completion to work correctly
    " as L will also include precending command before argument, eg.
    "   :QBLess test     <- A='test' L='QBLess test'
    call self._build(a:value)

    " send character data to completion func
    " and map flags back into results
    call self._match()
    let results = copy(self.data_results)
    return map(results, {_,val -> self.inputflags[0] . val . self.inputflags[1]})

endfunction

function! s:Expression._match() abort
    " TODO can add an optimisation step here
    " which checks whether the current expr is equal to previous expr
    " then use the previously generated results instead

    " alternatively, match() can return its result set from cached storage (as
    " it stores it now) or generate it if its out of date (ie. prompt expr
    " is not the same as the cached/stored version)

    let sm = self.hasflag_usealiases() ? s:enum_selectionmode.aliases
         \ : self.hasflag_usearglist() ? s:enum_selectionmode.arglist
         \ : self.hasflag_usenoname() ? s:enum_selectionmode.noname
         \ : self.is_number() ? s:enum_selectionmode.bufnr
         \ : s:enum_selectionmode.filepath

    let rs = s:matchfor_func_refs[sm](self.inputchars, {
        \ 'includecurrentbuffer': self.hasflag_includecurrentbuffer(),
        \ 'includedeletedbuffer': self.hasflag_bang(),
        \ })
    let self.data_selectionmode = sm
    " make sure resultset is always in a list not a single value
    let self.data_results = type(rs) == v:t_list ? rs : [rs]
endfunction

function! s:Expression._promptstr() abort
    " TODO use global switches to generate
    return '>> '
endfunction

function! s:Expression._convert2bufnr(value) abort
    if self.data_selectionmode == s:enum_selectionmode.filepath
        let bfnr = bufnr(a:value)

    elseif self.data_selectionmode == s:enum_selectionmode.aliases
        let bfnr = bufnr( s:aliases[a:value] )

    elseif self.data_selectionmode == s:enum_selectionmode.arglist
        let bfnr = bufnr(a:value)

    elseif self.data_selectionmode == s:enum_selectionmode.bufnr
        let bfnr = str2nr(a:value)

    elseif self.data_selectionmode == s:enum_selectionmode.noname
        let bfnr = str2nr(a:value)

    endif

    if bfnr <= 0
        throw 'buffer-not-exists'
    endif
    return bfnr

endfunction

function! s:Expression.resolve() abort
    call self._match()

    if len(self.data_results) == 0
        throw 'no-matches-found'
    endif

    if self.can_multiselect()
        let selc = self.multiselect()
        if selc is v:null
            throw 'no-match'
        endif
    else
        " otherwise always return the top match
        let selc = self.data_results[0]
    endif

    return self._convert2bufnr(selc)

endfunction

" name filter or scan or fetch?
function! s:Expression.fetch(limit=-1) abort
    call self._match()
    return self.data_results[:a:limit]
endfunction

function! s:Expression.prompt() abort
    " https://github.com/neovim/neovim/issues/16301
    " the definition needs to be an existing ref rather than a new lambda in 
    " this one line as the gb-collector will immediatly destroy it
    let expr = input(self._promptstr(), self.data_prefill, 'customlist,'.get(s:CompleteFuncLambdaWrapper, 'name'))
    let self.data_prefill = ''

    if empty(expr)
        throw 'exit-requested'
    endif

    call self._build(expr)

endfunction

function! s:Expression.set_expr(expr) abort
    call self._build(a:expr)
endfunction

" *** Expression Controls ***
function! s:Expression.can_switchto() abort
    return (s:switch_windowtoggle ? !s:switch_windowtoggle : self.hasflag_windowtoggle())
endfunction

function! s:Expression.can_multiselect() abort
    return (s:switch_multiselect ? !s:switch_multiselect : self.hasflag_multiselect())
endfunction

function! s:Expression.exit_requested() abort
    return self.data_exitrequested
endfunction

function! s:Expression.is_empty() abort
    return empty(self.inputchars)
endfunction

function! s:Expression.is_number() abort
    return match(self.inputchars, '^\d\+$') > -1
endfunction

" *** Expression Flags ***
function! s:Expression._flagmatch(expr) abort
    return match(self.inputflags[0] . self.inputflags[1], a:expr) > -1
endfunction

function! s:Expression.hasflag_usealiases() abort
    return self._flagmatch('#')
endfunction

function! s:Expression.hasflag_usearglist() abort
    return self._flagmatch('\$')
endfunction

function! s:Expression.hasflag_windowtoggle() abort
    return self._flagmatch('@')
endfunction

function! s:Expression.hasflag_multiselect() abort
    return self._flagmatch('?')
endfunction

function! s:Expression.hasflag_bang() abort
    return self._flagmatch('!')
endfunction

function! s:Expression.hasflag_usenoname() abort
    return self._flagmatch('!!')
endfunction

" request current buffer not be removed from results (this does not cancel
" mutliselect ? flag, as its meant to be used in conjunction)
function! s:Expression.hasflag_includecurrentbuffer() abort
    return self._flagmatch('??')
endfunction

" useful for using vim regex buffer selection
function! s:Expression.hasflag_usevimcompletion() abort
    return self._flagmatch('\^')
endfunction

"--------------------------------------------------
"   *** Expression Engine : Multiselection ***
"--------------------------------------------------
function! s:Expression.multiselect() abort
    let bflist = self.fetch( len(s:msw_selection_vals) )
    let idlist = map(copy(bflist), {i -> s:msw_selection_vals[i]})
    let ctxlist = map(copy(bflist), {_-> v:null})
    call s:multiselect_showlist(bflist, idlist, ctxlist)
    let selc = getcharstr()

    " match escape
    if match(selc, '') > -1
        throw 'exit-requested'
    endif

    " then sanitise all non-printable charcters (\p) and whitespace
    " (need to discard whole string when non-printables found, as keys like
    "  backspace <80>kb etc can also contain printables chars)
    let selc = match(selc, '[^[:print:]]\|\s') > -1 ? '' : selc
    if empty(selc)
        throw 'invalid-selection-input'
    endif

    " try match the request
    let idx = match(idlist, selc)
    if idx == -1
        let self.data_prefill = selc
        return v:null
    endif

    " hides the message display helper (press key to continue) on
    " successful selection
    redraw
    return bflist[idx]

endfunction

"--------------------------------------------------
"   *** Multiselect Display ***
"--------------------------------------------------
function! s:multiselect_showlist(rowvals, rowids, rowctxs) abort
    echo "\n"
    let idx = 0
    let idlast = len(a:rowvals)
    while idx < idlast
        " TODO support for neat-list
        " if exists('loaded_neatlist') else use generic
        call s:multiselect_showrow_generic(a:rowvals[idx], a:rowids[idx], a:rowctxs[idx])
        let idx += 1
    endwhile
endfunction

" @param records = bufitem
" @param id = value to show before item
" uses generic str value display so any list of str can be multiselected
function! s:multiselect_showrow_generic(val, id, ctx) abort
    echo '[' . a:id . '] ' . a:val . (empty(a:ctx) ? '' : ' : ' . a:ctx)
endfunction

"--------------------------------------------------
"   *** String Matching Functions ***
"--------------------------------------------------
" TODO BUG: on windows, paths with \ are breaking string matching for
" filepath and arglist
" matching can be fixed with substituting \\ with \\\\ but might need to do
" this globally for input expression?
"
" a workaround might be to set shellslash while doing the string match and 
" translating any input back slashes to forward slashes and reset setting on 
" complete
" ---

function! s:matchfor_filepath(value, opts={}) abort
    " TODO implement string match algo
    " - try case sensitive match first, then case insensitive
    " - multiple words (sep by space) for increasing accuracy of match

    " this algorithm will work on bufitems, but needs to return
    " raw full/relataive path matches

    " using normal vim completion while match algo is wip
    let rs = getcompletion(a:value, 'buffer')
    if !(a:opts->get('includecurrentbuffer', 0))
        let mybufnr = bufnr()
        call filter(rs, {_,val -> bufnr(val) != mybufnr})
    endif
    return rs
endfunction

function! s:matchfor_aliases(value, opts={}) abort
    return filter(keys(s:aliases), 'v:val =~ "^' . a:value .'"')
endfunction

function! s:matchfor_arglist(value, opts={}) abort
    let aglist = copy(argv())
    let value = s:forwardslash(a:value)
    return filter(aglist, {_,arg -> match(s:forwardslash(arg), value) > -1})
endfunction

function! s:matchfor_buffernumber(value, opts={}) abort
    let FuncRef = a:opts->get('includedeletedbuffer', 0) ? function('bufexists') : function('buflisted')
    return FuncRef(str2nr(a:value)) ? a:value : []
endfunction

function! s:matchfor_nonamebufs(value, opts={}) abort
    " TODO match value in the buffer itself using getbufline()
    " some sort of optimisation/caching needed before implementing this so that we
    " don't have to run the matches more than once when possible

    let nonamebufs = getbufinfo({'buflisted':1})
    let mybufnr = a:opts->get('includecurrentbuffer', 0) ? v:null : bufnr()
    call filter(nonamebufs, {_,val -> empty(val.name) && val.bufnr != mybufnr})
    call map(nonamebufs, {_,val -> val.bufnr})

    if empty(a:value)
        return nonamebufs
    else
        return match(nonamebufs, str2nr(a:value)) > -1 ? a:value : []
    endif

endfunction

" order as per enum_selectionmode
let s:matchfor_func_refs = [
    \ function('s:matchfor_filepath'),
    \ function('s:matchfor_aliases'),
    \ function('s:matchfor_arglist'),
    \ function('s:matchfor_buffernumber'),
    \ function('s:matchfor_nonamebufs')
    \ ]

"--------------------------------------------------
"   *** Plugin Interaction ***
"--------------------------------------------------
function! s:pub_prompt() abort
    call s:bcache_load()
    call s:Expression.reset()

    while 1
        try
            call s:Expression.prompt()
            let bnr = s:Expression.resolve()
            if bnr isnot v:null
                call s:goto_buffer(bnr, s:Expression.can_switchto())
                return
            endif

        catch /exit-requested/
            break
        catch /no-matches-found/
            call s:show_error('could not find any matches')
        catch /buffer-not-exists/
            call s:show_error('selected buffer could not be switched to')
        catch /invalid-selection-input\|no-match/
            " do nothing, re-runprompt
        endtry
    endwhile

    redraw

endfunction

" *** Show filtered buffer list only ***
function! s:pub_list(expr) abort
    " show result based on provided expr
    " ie. same as running prompt with flag ? and without the prompt 
    call s:bcache_load()
    call s:Expression.reset()
    call s:Expression.set_expr(a:expr)
    let blist = s:Expression.fetch()
    let idlist = map(copy(blist), 'v:val.bufnr')
    call s:buffer_list(blist, idlist)
endfunction

" *** Headless Mode ***
function! s:pub_less(expr) abort
    call s:bcache_load()
    call s:Expression.reset()
    call s:Expression.set_expr(a:expr)
    try
        let bnr = s:Expression.resolve()
        call s:goto_buffer(bnr, s:Expression.can_switchto())
    catch /no-matches-found/
        call s:show_error('could not find any matches')
    catch /no-match/
        call s:show_error('invalid selection')
    catch /exit-requested/
    endtry
endfunction

"--------------------------------------------------
"   *** Aliases ***
"--------------------------------------------------
function! s:alias_add(name, path) abort
    let s:aliases[a:name] = a:path
    call s:alias_serialise()
endfunction

function! s:alias_remove(name, path) abort
    call s:aliases->remove(name)
    call s:alias_serialise()
endfunction

function! s:alias_serialise() abort
    return 0
    " TODO regenerate global var
endfunction

"--------------------------------------------------
"   *** Helpers ***
"--------------------------------------------------
function! s:goto_buffer(bnr, switchtowindow=0) abort
    if a:switchtowindow
        let saved = &switchbuf
        let &switchbuf = 'useopen,usetab'
    endif

    try
        exec (a:switchtowindow && !empty(win_findbuf(a:bnr)) ? 's' : '') . 'buffer ' . a:bnr
    catch /E86/
        call s:show_error('could not switch to buffer ' . a:bnr)

    finally
        if exists('saved')
            let &switchbuf = saved
        endif
    endtry

endfunction

" (workaround) wrappers for assigning completion to prompt as dict
" function cannot be referenced (not sure if possible)
function! s:CompleteFuncWrapper(value, ...)
    " TODO think about workfow - where should we be loading the buffercache,
    " and resetting the expression
    "   - we need expression reset to tab complete
    "   - we also need buffer cache to tab complete ?
    call s:bcache_load()
    call s:Expression.reset()
    return s:Expression._complete(a:value)
endfunction

let s:CompleteFuncLambdaWrapper = {a, ... -> s:CompleteFuncWrapper(a)}

function! s:complete_aliases(A, ...)
    return s:matchfor_aliases(a:A)
endfunction

function! s:show_error(msg)
    echohl Error
    echo "\n".a:msg
    echohl None
endfunction

function! s:forwardslash(path)
    return substitute(a:path, '\', '/', 'g')
endfunction

function! s:debug(...)
    echo "\n-----DEBUG~PAUSE-----"
    for msg in a:000
        echo string(msg)
    endfor
    echo '---------------------'
    call getchar()
endfunction

"--------------------------------------------------
"   *** Commands ***
"--------------------------------------------------
command! QBAliasList echo s:aliases
command! -nargs=1 QBAliasAdd call s:alias_add(<q-args>, expand("%:p"))
command! -nargs=1 -complete=customlist,s:complete_aliases QBAliasRemove call s:alias_remove(<q-args>)
command! -nargs=* QBList call s:pub_list(<q-args>)
command! -nargs=+ -complete=customlist,s:CompleteFuncWrapper QBLess call s:pub_less(<q-args>)
command! QBPrompt call s:pub_prompt()

exe 'command! -nargs=* -complete=customlist,s:CompleteFuncWrapper '.s:custom_commandname.' if empty(<q-args>)<bar>call s:pub_prompt()<bar>else<bar>call s:pub_less(<q-args>)<bar>endif' 


" testing only
ca QBAA QBAliasAdd
ca QBAR QBAliasRemove
ca QBAL QBAliasList
ca QBP QBPrompt
command! -nargs=+ -complete=customlist,s:CompleteFuncWrapper B call s:pub_less(<q-args>)
nnoremap <space><space> :Quick<cr>

