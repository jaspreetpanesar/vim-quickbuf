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
let g:QuickBuf_switch_windowtoggle = 0
let g:QuickBuf_switch_multiselect = 0
let g:QuickBuf_multiselection_keys = s:c_mselvals
let g:QuickBuf_easycommandname = "QuickBuffer"

"--------------------------------------------------
"   *** GLOBALS ***
"--------------------------------------------------
let s:aliases = {}
let s:buffercache = []

""--------------------------------------------------
""   *** Buffer Context Items ***
""--------------------------------------------------
"let s:bufitem = {
"\ 'name': '',
"\ 'context': '',
"\ 'relpath': '',
"\ 'fullpath': '',
"\ 'bufnr': '',
"\ 'is_modified': 0,
"\ 'is_current': 0,
"\ 'is_alternate': 0,
"\ 'is_noname': 0,
"\ }
"
"" TODO this should only be happening once per buffer lifetime
"function! s:bufitem.new(binfo) abort
"    let item = copy(self)
"    call item._gen(a:binfo)
"    return item
"endfunction
"
"" renegrate minimal amount of data
"" ie. context, and flags
"" will be run everytime before item is shown
"function! s:bufitem.upd(binfo) abort
"    " update flags is_current, is_alternate, is_modified
"    " update context
"endfunction
"
"" regenerate all data
"function! s:bufitem.regen() abort
"    let binfo = getbufinfo(self.bufnr)
"    call self._gen(binfo)
"endfunction
"
"function! s:bufitem._gen(binfo) abort
"    let self.bufnr = a:binfo.bufnr
"    let self.is_current = (bufnr() == self.bufnr)
"    let self.is_alternate = (bufnr('#') == self.bufnr)
"    let self.is_modified = a:binfo.changed
"
"    let path = a:binfo.name
"    if empty(path)
"        let self.is_noname = 1
"        let self.name = '#'.self.bufnr
"   else
"        let self.fullpath = path
"        let self.relpath = fnamemodify(path, ':.')
"        let self.name = fnamemodify(path, ':t')
"        let self.context = fnamemodify(path, ':h')
"    endif
"
"endfunction
"
"function! s:bufitem.tostring() abort
"    return self.name . ' (' . self.context . ')'
"endfunction
"
"" TODO cache this list with autocmds ?
"function! s:bcache_load() abort
"    let items = []
"    for buf in getbufinfo({'buflisted':1})
"        call add(items, s:bufitem.new(buf))
"    endfor
"    let s:buffercache = items
"endfunction

"--------------------------------------------------
"   *** Expression Engine ***
"--------------------------------------------------
let s:Expression = {}

function! s:Expression.reset() abort
    let self.input = ''
    let self.inputchars = ''
    let self.inputflags = ['', '']
    let self.data_prefill = ''
    let self.data_matches = []
    let self.cachectx_inputchars = ''
    let self.cachectx_selectionmode = ''
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
    return map(copy(self.data_matches), {_,val -> self.inputflags[0] . val.value . self.inputflags[1]})

endfunction

function! s:Expression._can_use_cache(mode)
    " TODO what happens with empty cached results?
    " check flags too?
    if empty(self.data_matches)
        call s:debug('can_use_cache(): no matches exist')
        return 0
    elseif a:mode != self.cachectx_selectionmode
        call s:debug('can_use_cache(): selection mode is different')
        return 0
    " elseif empty(self.inputchars) != empty(self.cachectx_inputchars)
    "     call s:debug('can_use_cache(): input empty/not', self.inputchars, self.cachectx_inputchars)
    "     return 0
    elseif match(map(copy(self.data_matches), {_,v -> v.value}), self.inputchars) < 0 && self.input != self.cachectx_inputchars
        call s:debug('can_use_cache(): input not matches anything', map(copy(self.data_matches), {_,v -> v.value}), self.input)
        return 0
    endif
    call s:debug('can_use_cache(): true')
    return 1
endfunction

function! s:Expression._match() abort

    " TESTING using shellslash mode to blanket avoid issues with forward
    " slashe pattern matching on windows
    let slashsave = &shellslash
    let &shellslash = 1
    let userinput = s:forwardslash(self.inputchars)

    while 1
        let mode = self.hasflag_usealiases() ? s:enum_selectionmode.aliases
             \ : self.hasflag_usearglist() ? s:enum_selectionmode.arglist
             \ : self.hasflag_usenoname() ? s:enum_selectionmode.noname
             \ : self.is_number() ? s:enum_selectionmode.bufnr
             \ : s:enum_selectionmode.filepath

        " TODO should we move the mode check here?
        if mode == self.cachectx_selectionmode && self._can_use_cache(mode)
            call s:debug('using cache', self.data_matches)

            " TODO filter the matches again based on the latest prompt value
            " but doing this we're basically discarding the results, is that
            " what we want to be doing?
            " doing it this way, we wouldn't want this system to be called
            " 'cache', and should be moreso 'can_use_autocomplete' as a method
            " of optimisation rather than a cache
            " ^ in essence, if we have a set of results already, and those 
            " results can be deemed to be 'valid', then use them now

            " if previous results exist (and we can use the cache) and the new input 
            " is different, then best case we probably are using one of the
            " autocompleted results (either exactly, or partially) so try
            " and filter to remove any of the unecessary entries

            " if the previous search and current search are different (like we
            " may be searching with an autocompleted entry) then filter - but if
            " it's the same as before then leave matches as they are
            if userinput != self.cachectx_inputchars
                " \ && match(map(copy(self.data_matches), {_,v -> v.value}), userinput) >= 0
                call s:debug('filtering previous matches on ' . userinput)
                call filter(self.data_matches, {_,v -> match(v.value, userinput) > -1})
                call s:debug(self.data_matches)
            endif

            if len(self.data_matches) > 0
                break
            endif
            call s:debug('cache / filter completed with no results')

        endif

        call s:debug('generating matches')

        let results = []
        call s:matchfor_func_refs[mode](results, userinput, {
            \ 'includecurrentbuffer': self.hasflag_includecurrentbuffer(),
            \ 'includedeletedbuffer': self.hasflag_bang(),
            \ })

        let self.cachectx_inputchars = userinput
        let self.cachectx_selectionmode = mode
        let self.data_matches = results

        break
    endwhile

    let &shellslash = slashsave

endfunction

function! s:Expression._promptstr() abort
    " TODO use global switches to generate
    return '>> '
endfunction

function! s:Expression.resolve() abort
    call self._match()
    let matches = self.data_matches

    if len(matches) == 0
        throw 'no-matches-found'
    endif

    if self.can_multiselect()
        let selc = self.multiselect(matches)
        if selc is v:null
            throw 'no-match'
        endif
    else
        " otherwise always return the top match
        let selc = matches[0]
    endif

    if selc.bufnr <= 0
        throw 'buffer-not-exists'
    endif
    return selc.bufnr

endfunction

" name filter or scan or fetch?
function! s:Expression.fetch(limit=-1) abort
    call self._match()
    return self.data_matches[:a:limit]
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
    return (g:QuickBuf_switch_windowtoggle ? !g:QuickBuf_switch_windowtoggle : self.hasflag_windowtoggle())
endfunction

function! s:Expression.can_multiselect() abort
    " TODO need to rethink this, we should move the len check out of here?
    return (g:QuickBuf_switch_multiselect && len(self.data_matches) > 1 ? !self.hasflag_multiselect() : self.hasflag_multiselect())
    " switch =    1   0   1   1
    " count  =    2   2   1   2
    " flag   =    1   1   1   0
    " ms?..       0   1   1   1
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
" multiselect ? flag, as its meant to be used in conjunction)
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
function! s:Expression.multiselect(matches) abort
    " TODO can this be done better?
    let matches = a:matches[:len(g:QuickBuf_multiselection_keys)-1]

    let items   = map(copy(matches), {_, v -> v.repr })
    let idlist  = map(copy(items),   {i -> g:QuickBuf_multiselection_keys[i]})
    let ctxlist = map(copy(items),   {_-> v:null})

    call s:multiselect_showlist(items, idlist, ctxlist)
    " let selc = getcharstr()
    let selc = nr2char(getchar())

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
    return matches[idx]

endfunction

"--------------------------------------------------
"   *** Multiselect Display ***
"--------------------------------------------------
function! s:multiselect_showlist(rowvals, rowids, rowctxs) abort
    echo "\n"
    let idx = 0
    let idlast = len(a:rowvals)
    while idx < idlast
        " TODO(future) support for neat-list
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

function! s:new_match_item(val, bufnr, repr, ctx='')
    return { 'value':a:val, 'bufnr':a:bufnr, 'repr':a:repr, 'ctx':a:ctx }
endfu

function! s:matchfor_filepath(results, value, opts={}) abort
    " TODO implement string match algo
    " - try case sensitive match first, then case insensitive
    " - multiple words (sep by space) for increasing accuracy of match

    " this algorithm will work on bufitems, but needs to return
    " raw full/relataive path matches

    " - every buffer will be given a score based on the matching technique
    " - in the end, the results will be collated by 
    "     - retrieve highest score in results
    "     - filter and keep results that are equal to hightest score

    " using normal vim completion while match algo is wip
    let matches = getcompletion(a:value, 'buffer')
    if !(a:opts->get('includecurrentbuffer', 0))
        let mybufnr = bufnr()
        call filter(matches, {_,val -> bufnr(val) != mybufnr})
    endif

    for m in matches
        call add(a:results, s:new_match_item(m, bufnr(m), m) )
    endfor

endfunction

function! s:matchfor_aliases(results, value, opts={}) abort
    for m in filter(keys(s:aliases), {_,val -> val =~? a:value})
        call add(a:results, s:new_match_item(m, s:aliases[m], m) )
    endfor
endfunction

function! s:matchfor_arglist(results, value, opts={}) abort
    let aglist = copy(argv())
    for m in filter(aglist, {_,arg -> match(arg, a:value) > -1})
        call add(a:results, s:new_match_item(m, bufnr(m), m) )
    endfor
endfunction

function! s:matchfor_buffernumber(results, value, opts={}) abort
    let FuncRef = a:opts->get('includedeletedbuffer', 0) ? function('bufexists') : function('buflisted')
    if FuncRef(str2nr(a:value)) 
        call add(a:results, s:new_match_item(a:value, a:value, a:value))
    endif
endfunction

function! s:matchfor_nonamebufs(results, value, opts={}) abort
    " retrieve all noname buffers
    let nonamebufs = getbufinfo({'buflisted':1})

    " remove current buffer from list
    let mybufnr = a:opts->get('includecurrentbuffer', 0) ? v:null : bufnr()
    call filter(nonamebufs, {_,val -> empty(val.name) && val.bufnr != mybufnr})

    if !empty(a:value)
        " TODO this is disabled for the moment (not sure if i want it)
        if 0 && s:isnumber(a:value) && match(map(copy(nonamebufs), {_,v -> v.bufnr}), a:value) > -1
            " filter to specific buffer by bufnr
            call filter(nonamebufs, {_,v -> v.bufnr == a:value})
        else
            " filter to buffers that cantain the provided string
            " TODO configrable option for how many lines to check
            call filter(nonamebufs, {_,val -> match( s:filtered_getbufline(val.bufnr, 50), a:value ) > -1})
        endif
    endif

    for b in nonamebufs
        let bufnr = b.bufnr
        call add(a:results, s:new_match_item(bufnr, bufnr, '[No Name #'.bufnr.']'))
    endfor

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
" TODO looks like this has been broken for a whlie?
function! s:pub_list(expr) abort
    " show result based on provided expr
    " ie. same as running prompt with flag ? and without the prompt 
    call s:Expression.reset()
    call s:Expression.set_expr(a:expr)
    let matches = s:Expression.fetch()
    let idlist = map(copy(blist), 'v:val.bufnr')
    call s:buffer_list(blist, idlist)
endfunction

" *** Headless Mode ***
function! s:pub_less(expr) abort
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
function! s:alias_add(name, bufnr) abort
    if match(a:name, '[^a-zA-Z0-9]') > -1
        call s:show_error('alias name invalid - must be alphanumeric characters only')
    else
        let s:aliases[a:name] = a:bufnr
        call s:alias_serialise()
        echo "alias added '" . a:name . "'"
    endif
endfunction

function! s:alias_remove(name) abort
    if s:aliases->has_key(a:name)
        call remove(s:aliases, a:name)
        call s:alias_serialise()
        echo "alias removed '" . a:name . "'"
    else
        call s:show_error('alias "' . a:name . '" does not exist')
    endif
endfunction

" TODO call this on BufDelete
function! s:alias_serialise() abort
    let data = []
    for key in keys(s:aliases)
        let val = s:aliases[key]
        let path = expand('#'.val.':p')
        if !empty(path)
            call add(data, key.'#'.path)
        endif
    endfor
    let g:QuickBufAliases = join(data, ',')
endfunction

" TODO call this on SessionLoadPost
function! s:alias_deserialise() abort
    let s:aliases = {}
    for value in split(get(g:, 'QuickBufAliases', ""), ',')
        let data = split(value, '#')
        let bufnr = bufnr(data[1])
        if !empty(bufnr)
            let s:aliases[data[0]] = bufnr
        endif
    endfor
endfunction

"--------------------------------------------------
"   *** Helpers ***
"--------------------------------------------------
function! s:goto_buffer(bnr, switchifopen=0) abort
    if a:switchifopen
        let saved = &switchbuf
        let &switchbuf = 'useopen,usetab'
    endif

    try
        exec (a:switchifopen && !empty(win_findbuf(a:bnr)) ? 's' : '') . 'buffer ' . a:bnr
    catch /E86/
        call s:show_error('could not open buffer ' . a:bnr)

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
    call s:Expression.reset()
    return s:Expression._complete(a:value)
endfunction

let s:CompleteFuncLambdaWrapper = {a, ... -> s:CompleteFuncWrapper(a)}

function! s:complete_aliases(A, ...)
    let res = []
    call s:matchfor_aliases(res, a:A)
    return map(res, {_,v -> v.value})
endfunction

function! s:complete_none(...)
    return []
endfunction

function! s:show_error(msg)
    echohl Error
    echo "\n".a:msg
    echohl None
endfunction

function! s:forwardslash(path)
    return substitute(a:path, '\', '/', 'g')
endfunction

" returns the specified amount of lines starting from the first
" non-blank line
function! s:filtered_getbufline(bufnr, max)
    let lines = getbufline(a:bufnr, 1, '$')
    for i in range(len(lines))
        if !empty(lines[i])
            let lines = lines[i:]
            break
        endif
    endfor
    return lines[:(a:max)]
endfunction

function! s:isnumber(val)
    return match(a:val, '[^[:digit:]]') == -1
endfunction

if 0
    function! s:debug(...)
        echo "\n-----DEBUG~PAUSE-----"
        for msg in a:000
            echo string(msg)
        endfor
        echo '---------------------'
        call getchar()
    endfunction
else
    let s:debuglog = []
    function! s:debug(...)
        for msg in a:000
            call add(s:debuglog, string(msg))
        endfor
    endfunction
    command! QBDebugLog for m in s:debuglog<bar>echo m<bar>endfor
endif

"--------------------------------------------------
"   *** Commands ***
"--------------------------------------------------
command! QBAliasList echo s:aliases
command! -nargs=1 QBAliasAdd call s:alias_add(<q-args>, bufnr())
command! -nargs=1 -complete=customlist,s:complete_aliases QBAliasRemove call s:alias_remove(<q-args>)
command! -nargs=* QBList call s:pub_list(<q-args>)
command! -nargs=+ -complete=customlist,s:CompleteFuncWrapper QBLess call s:pub_less(<q-args>)
command! QBPrompt call s:pub_prompt()

exe 'command! -nargs=* -complete=customlist,s:CompleteFuncWrapper '.g:QuickBuf_easycommandname.' if empty(<q-args>)<bar>call s:pub_prompt()<bar>else<bar>call s:pub_less(<q-args>)<bar>endif' 


" testing only
ca QBAA QBAliasAdd
ca QBAR QBAliasRemove
ca QBAL QBAliasList
ca QBP QBPrompt
command! -nargs=+ -complete=customlist,s:CompleteFuncWrapper B call s:pub_less(<q-args>)
nnoremap <space><space> :Quick<cr>

call s:alias_deserialise()


