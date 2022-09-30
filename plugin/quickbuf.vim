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
let s:c_mselvals = '1234abcdef' " TODO make configurable
let s:c_mselmax = 10

"--------------------------------------------------
"   *** CONFIGURATION ***
"--------------------------------------------------
" TODO convert to global variables
let s:switch_windowtoggle = 0
let s:switch_multiselect = 0
let s:msw_selection_vals = s:c_mselvals

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
\ 'fullpath': '',
\ 'bufnr': '',
\ 'is_modified': 0,
\ 'is_current': 0,
\ 'is_alternate': 0,
\ 'is_noname': 0,
\ }

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
        let self.noname = 1
        let self.name = '#'.self.bufnr
   else
        let self.fullpath = path
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
let s:Expression = {
\ 'input': '',
\ 'inputflags': ['', ''],
\ 'inputchars': '',
\ 'data_prefill': '',
\ 'data_lastrequest': '',
\ 'data_results': [],
\ 'data_exitrequested': [],
\ }

" TODO this should be unused now? where to cache (if that's still needed)
function! s:Expression.new() abort
    let o = copy(self)
    call o._cache()
    return o
endfunction

function! s:Expression.reset() abort
    let self.data_prefill = '' 
endfunction

function! s:Expression._cache() abort
endfunction

function! s:Expression._build(expr) abort
    let self.input = a:expr

    if empty(a:expr)
        return
    endif

    " TODO what do to do about extra spaces? as i want to support multiple
    " input words for increasing accuracy of match

    " limit filename character scope to alphanumeric and _-%.
    let pos = matchstrpos(a:expr, '[a-zA-Z0-9\._\-%]\+')
    let self.inputchars = pos[0]
    if pos[1] > -1
        let self.inputflags[0] = pos[1] > 0 ? a:expr[:(pos[1]-1)] : ''
        let self.inputflags[1] = a:expr[pos[2]:]
    else
        " when no characters were found (ie. prompt empty)
        let self.inputflags = [a:expr, '']
    endif

endfunction

function! s:Expression._complete(A, L, P) abort
    " buiild first to retrieve context
    call self._build(a:A) " need to use A (not L) for :command completion to work correctly

    if self.is_empty()
        return self.input " TODO should this be removed?
    endif

    " TODO (future) determine completion mode based on flag nearest to end rather than a precedence level?

    let FuncRef = self.flag_usealiases() ?  function('s:complete_aliases') : self.flag_usearglist() ?  function('s:complete_arglist') : function('s:complete_buffers')

    " send character data to completion func
    " and map flags back into results
    let results = FuncRef(a:A, a:L, a:P)
    return map(results, {_,val -> self.inputflags[0] . val . self.inputflags[1]})

endfunction

function! s:Expression._match() abort
    " TODO implement string match algo
    " try case sensitive match first, then case insensitive
    let res = copy(s:buffercache)
    let self.data_results = res

endfunction

function! s:Expression.resolve() abort
    call self._match()

    if self.can_multiselect()
        let sel = self.multiselect()
        if sel isnot v:null
            return sel.fullpath
        else
            throw 'invalid-selection'
        endif
    endif

    " otherwise always select top result
    if len(self.data_results) > 0
        return self.data_results[0].fullpath
    else
        throw 'no-matches-found'
    endif

endfunction

" name filter or scan or fetch?
function! s:Expression.fetch(limit=-1) abort
    call self._match()
    return self.data_results[:a:limit]
endfunction

function! s:Expression.prompt() abort
    " TODO does this work for normal vim? (workaround for assigning script
    " file complete func in nvim not working)
    " https://github.com/neovim/neovim/issues/16301
    let expr = input(self.promptstr(), self.data_prefill, 'customlist,'.get(s:CompleteFuncLambdaWrapper, 'name'))

    let self.data_prefill = ''

    if empty(expr)
        let self.data_exitrequested = 1
    else
        let self.data_exitrequested = 0
        call self._build(expr)
    endif

endfunction

function! s:Expression.set_expr(expr) abort
    call self._build(a:expr)
endfunction

function! s:Expression.promptstr() abort
    return '> '
endfunction

" *** Expression Controls ***
function! s:Expression.can_switchto() abort
    return (s:switch_windowtoggle ? !s:switch_windowtoggle : self.flag_windowtoggle())
endfunction

function! s:Expression.can_multiselect() abort
    return (s:switch_multiselect ? !s:switch_multiselect : self.flag_multiselect())
endfunction

function! s:Expression.exit_requested() abort
    return self.data_exitrequested
endfunction

function! s:Expression.is_empty() abort
    return empty(self.inputchars)
endfunction

" *** Expression Derived Values ***
function! s:Expression._hasflag(flag) abort
    return match(self.inputflags[0] . self.inputflags[1], a:flag) > -1
endfunction

function! s:Expression.flag_usealiases() abort
    return self._hasflag('#')
endfunction

function! s:Expression.flag_usearglist() abort
    return self._hasflag('\$')
endfunction

function! s:Expression.flag_windowtoggle() abort
    return self._hasflag('@')
endfunction

function! s:Expression.flag_multiselect() abort
    return self._hasflag('?')
endfunction

"--------------------------------------------------
"   *** Expression Engine : Multiselection ***
"--------------------------------------------------
function! s:Expression.multiselect() abort
    " generate selection values for each record
    let blist = self.fetch(9)
    let idlist = map(copy(blist), {i -> s:msw_selection_vals[i]})

    " show buffers
    call s:buffer_list(blist, idlist)

    " listen for choice
    let sel = getcharstr()

    " special values like  will return a null value rather than
    " raise an selection error
    if match(sel, '\|\| ') >= 0
        return v:null
    endif

    " sanitise selection
    let sel_st = substitute(sel, '[^a-zA-Z0-9]', '', 'g')

    if empty(sel)
        throw 'no-selection'
    endif

    let idx = index(s:msw_selection_vals, sel_st)
    if idx >= 0
        return blist[idx]
    else
        let self.data_prefill = sel
        throw 'invalid-selection'
    endif

endfunction

"--------------------------------------------------
"   *** Buffer List Display ***
"--------------------------------------------------
function! s:buffer_list(records, ids) abort
    let idx = 0
    let idlast = len(a:records)
    while idx < idlast
        call s:buffer_list_row(a:ids[idx], a:records[idx])
        let idx += 1
    endwhile
endfunction

" @param records = bufitem
" @param id = value to show before item
function! s:buffer_list_row(id, row) abort
    echo '[' . a:id . '] ' . a:row.tostring()
endfunction

"--------------------------------------------------
"   *** Autocomplete Functions ***
"--------------------------------------------------
function! s:complete_buffers(A, L, P) abort
    return ["buffer1", "buffer2"]
endfunction

function! s:complete_aliases(A, L, P) abort
    return filter(s:aliases, {key, val -> val =~? a:A})
endfunction

function! s:complete_arglist(A, L, P) abort
    return ["arg1", "arg2"]
endfunction

"--------------------------------------------------
"   *** Plugin Interaction ***
"--------------------------------------------------
function! s:pub_prompt() abort
    call s:bcache_load()
    call s:Expression.reset()

    while 1
        call s:Expression.prompt()

        try
            if !s:Expression.exit_requested()
                let path = s:Expression.resolve()
                call s:switch_buffer(path, s:Expression.can_switchto())
            endif
            return

        catch /no-matches-found/
            call s:show_error('no matches found')
        catch /invalid-selection/
            " do nothing, re-run prompt
        endtry

    endwhile
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
        let path = s:Expression.resolve()
        call s:switch_buffer(path, s:Expression.can_switchto())
    catch /no-matches-found/
        call s:show_error('no matches found')
    endtry
endfunction

"--------------------------------------------------
"   *** Goto Buffer ***
"--------------------------------------------------
function! s:switch_buffer(path, switchto=0) abort
    if a:switchto
        let save = &switchbuf
        let &switchbuf = 'useopen,usetab'
    endif
    " might not need this try-catch
    try
        exec (a:switchto ? 's' : '') . 'buffer ' . a:path
    catch /E94/
        echoerr 'could not switch to buffer ' . a:path

    finally
        if a:switchto
            let &switchbuf = save
        endif
    endtry
endfunction

"--------------------------------------------------
"   *** Aliases ***
"--------------------------------------------------
function! s:alias_add(name, path) abort
    let s:aliases[a:name] = a:path
    call s:alias_sync()
endfunction

function! s:alias_remove(name, path) abort
    call s:aliases->remove(name)
    call s:alias_sync()
endfunction

function! s:alias_sync() abort
    return 0
    " TODO regenerate global var
endfunction

"--------------------------------------------------
"   *** Helpers ***
"--------------------------------------------------
" (workaround) wrapper for assigning completion to prompt as dict
" function cannot be referenced (not sure if possible)
function! s:CompleteFuncWrapper(A, L, P)
    return s:Expression._complete(a:A, a:L, a:P)
endfunction

let s:CompleteFuncLambdaWrapper = {a,l,p -> s:Expression._complete(a,l,p)}

"--------------------------------------------------
"   *** Commands ***
"--------------------------------------------------
command! -nargs=1 QBAliasAdd call s:alias_add(<q-args>, expand("%:p"))
command! -nargs=1 -complete=customlist,s:complete_aliases QBAliasRemove call s:alias_remove(<q-args>)
command! -nargs=* QBList call s:pub_list(<q-args>)
command! -nargs=+ -complete=customlist,s:CompleteFuncWrapper QBLess call s:pub_less(<q-args>)
command! QBPrompt call s:pub_prompt()


