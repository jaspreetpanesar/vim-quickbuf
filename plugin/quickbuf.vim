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
"   *** GLOBALS ***
"--------------------------------------------------
let s:oexpr = v:none
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
    self.bufnr = a:binfo.bufnr
    call self._gen(a:binfo)
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
    " assumes self.bufnr is already set

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
    return self.name + ' : ' + self.context
endfunction

" TODO cache this list with autocmds ?
function! s:bcache_load() abort
    let items = []
    for buf in getbufinfo({'buflisted':1})
        call items->add(s:bufitem.new(buf))
    endfor
    let s:buffercache = items
endfunction

"--------------------------------------------------
"   *** Expression Engine ***
"--------------------------------------------------
let s:Expression = {
\ 'input': '',
\ 'inputf_flags': '',
\ 'inputf_chars': '',
\ 'flag_usealiases': 0,
\ 'flag_usearglist': 0,
\ 'flag_windowtoggle': 0,
\ 'data_prefill': '',
\ 'data_lastrequest': '',
\ 'data_lastresults': [],
\ }

function! s:Expression.new() abort
    let o = copy(self)
    call o._cache()
    return o
endfunction

function! s:Expression._cache() abort
endfunction

function! s:Expression.complete(A, C, P) abort
    " buiild first to retrieve context
    call self.build(a:C)

    " determine which completion algo to use
    if self.is_empty()
        return self.input

    if self.flag_usealiases
        let cfunc = function('s:complete.aliases')
    elseif self.flag_usearglist
        let cfunc = function('s:complete.arglist')
    else
        let cfunc = function('s:complete.buffers')
    endif

    " send character data to completion func
    " let results = cfunc()
    " map() flags back into result values

endfunction

function! s:Expression.build(expr) abort
    let self.input = a:expr
endfunction

" returns path or v:none
function! s:Expression.resolve() abort
    call self.build()
    " TODO determine nearest path from input
    " and run multi selection matches where required
    return get(self.data_lastrequest, 0, v:none)
endfunction

function! s:Expression.prompt() abort
    self.input = input(self.promptstr, self.data_prefill, 'customlist,' . string(function('self.complete')))
endfunction

function! s:Expression.can_switchto() abort
    " TODO resolve based on global toggle
    return self.flag_windowtoggle
endfunction

function! s:Expression.exit_requested() abort
    return 0
endfunction

function! s:Expression.prefill(val) abort
    self.data_prefill = val
endfunction

function! s:Expression.is_empty() abort
    return empty(self.input)
endfunction

function! s:Expression.multiselect() abort
endfunction

"--------------------------------------------------
"   *** Multiselection Display ***
"--------------------------------------------------
" filename, context, id, is_modified, is_current,
" is_alternate
function! s:multiselection_list(rows) abort
endfunction

function! s:multiselection_list_row(row) abort
endfunction

"--------------------------------------------------
"   *** Autocomplete Functions ***
"--------------------------------------------------
function! s:complete_buffers(A, C, P) abort
endfunction

function! s:complete_aliases(A, C, P) abort
endfunction

function! s:complete_arglist(A, C, P) abort
endfunction

"--------------------------------------------------
"   *** Prompt ***
"--------------------------------------------------
function! s:run_prompt() abort
    let s:oexpr = s:Expression.new()
    call s:bcache_load()

    while 1
        call s:oexpr.prompt()
        let path = s:oexpr.resolve()

        if path isnot v:none
            call s:switch(path, s:oexpr.can_switchto())
            return

            " TODO for now, always break until theres a solution for
            " determining a requested exit from the prompt
            break

        " elseif s:oexpr.exit_requested()
        "     return
        "
        " else
        "     call show_error('no matches could be found')
        "     call s:oexpr.prefill(s:oexpr.last_request)

        endif

    endwhile

endfunction

"--------------------------------------------------
"   *** Goto Buffer ***
"--------------------------------------------------
function! s:switch_buffer(path, switchto=0) abort
    if a:switchto
        let save = &switchbuf
        let &switchbuf = useopen,usetab
    endif
    " TODO might not need this try-catch
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
" command -nargs=1 QBAliasAdd call s:alias_add(<args>, expand("%:p"))
" command -nargs=1 QBAliasRemove call s:alias_remove(<args>)
" command QBRunPrompt call s:run_prompt()

