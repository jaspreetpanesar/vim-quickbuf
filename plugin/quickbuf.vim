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
let s:c_selvals = '012345689abcdefghijklmnopqrstuvwxyz' " TODO make configurable

"--------------------------------------------------
"   *** GLOBALS ***
"--------------------------------------------------
let s:oexpr = v:null
let s:aliases = {}
let s:buffercache = {}

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
\ 'inputf_flagsbefore': '',
\ 'inputf_flagsafter': '',
\ 'inputf_chars': '',
\ 'flag_usealiases': 0,
\ 'flag_usearglist': 0,
\ 'flag_windowtoggle': 0,
\ 'flag_multiselect': 0,
\ 'data_prefill': '',
\ 'data_lastrequest': '',
\ 'data_lastresults': [],
\ 'data_exitrequested': [],
\ }

function! s:Expression.new() abort
    let o = copy(self)
    call o._cache()
    return o
endfunction

function! s:Expression._cache() abort
endfunction

function! s:Expression._complete(A, L, P) abort
    " buiild first to retrieve context
    call self.build(a:L)

    " determine which completion algo to use
    if self.is_empty()
        return self.input
    endif

    " TODO determine completion mode based on flag nearest to end rather
    " than a precedence level?
    if self.flag_usealiases
        let cfunc = function('s:complete_aliases')
    elseif self.flag_usearglist
        let cfunc = function('s:complete_arglist')
    else
        let cfunc = function('s:complete_buffers')
    endif

    " send character data to completion func
    " let results = cfunc()
    " map() flags back into result values

endfunction

function! s:Expression._build(expr) abort
    let self.input = a:expr
    " TODO generate expression data
endfunction

function! s:Expression._match() abort
    " TODO implement string match algo
    let res = copy(s:buffercache)
    let self.data_lastresults = res
endfunction

function! s:Expression.resolve() abort
    call self._match()

    if self.can_multiselect()
        return self.multiselect()
    endif

    " otherwise always select top result
    if len(self.data_lastresults) > 0
        return self.data_lastresults[0]
    else
        throw 'no-matches-found'
    endif

endfunction

" name filter or scan or fetch?
function! s:Expression.fetch(limit=-1) abort
    call self._match()
    return self.data_lastresults[:a:limit]
endfunction

function! s:Expression.prompt() abort
    let expr = input(self.promptstr, self.data_prefill, 'customlist,' . string(function('self._complete')))
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

function! s:Expression.can_switchto() abort
    " TODO resolve based on global toggle + flag
    return self.flag_windowtoggle
endfunction

function! s:Expression.can_multiselect() abort
    " TODO resolve based on global option + flag
    return self.flag_multiselect
endfunction

function! s:Expression.exit_requested() abort
    return self.data_exitrequested
endfunction

"--------------------------------------------------
"   *** Expression Engine : Multiselection ***
"--------------------------------------------------
function! s:Expression.multiselect() abort
    " generate selection values for each record
    let blist = self.fetch(9)
    let idlist = []
    let idx = 1
    for item in blist
        call idlist->add(s:c_selvals[idx])
        let idx += 1
    endfor

    " show buffers
    call s:buffer_list(blist, idlist)

    " listen for selection
    let sel = getcharstr()
    " TODO sanitise values like 

    if empty(sel)
        throw 'no-selection'
    endif

    let idx = " TODO selection to list index
    if idx >= 0
        return self.data_lastresults[idx]
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
endfunction

function! s:complete_aliases(A, L, P) abort
endfunction

function! s:complete_arglist(A, L, P) abort
endfunction

"--------------------------------------------------
"   *** Plugin Interaction ***
"--------------------------------------------------
function! s:pub_prompt() abort
    call s:bcache_load()
    let s:oexpr = s:Expression.new()

    while 1
        call s:oexpr.prompt()

        try
            if !s:oexpr.exit_requested()
                let path = s:oexpr.resolve()
                call s:switch(path, s:oexpr.can_switchto())
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
    let s:oexpr = s:Expression.new()
    call s:oexpr.set_expr(a:expr)
    let blist = s:oexpr.fetch()
    let idlist = copy(blist)
    call map(idlist, 'v:val.bufnr')
    call s:buffer_list(blist, idlist)
endfunction

" *** Headless Mode ***
function! s:pub_less(expr) abort
    call s:bcache_load()
    let s:oexpr = s:Expression.new()
    call s:oexpr.set_expr(a:expr)
    try
        let path = s:oexpr.resolve()
        call s:switchto(path, s:oexpr.can_switchto())
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
        let &switchbuf = useopen,usetab
    endif
    " might not need this try-catch
    try
        exec (a:switchto ? 's' : '') . 'buffer ' . a:path
    catch /E-94/
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
"   *** Commands ***
"--------------------------------------------------
command! -nargs=1 QBAliasAdd call s:alias_add(<args>, expand("%:p"))
command! -nargs=1 -complete=customlist,s:complete_aliases QBAliasRemove call s:alias_remove(<args>)
command! -nargs=* QBList call s:pub_list(<q-args>)
command! -nargs=+ QBLess call s:pub_less(<q-args>)
command! QBPrompt call s:pub_prompt()

