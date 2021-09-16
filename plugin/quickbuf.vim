"
" *QuickBuf* Creates a prompt to allow for quick
"   \ and non-intrusive buffer switching
" Author:      Jaspreet Panesar <jaspreetpanesar>
" Version:     2.0
" Last Change: 2020 Apr 12
" Licence:     This file is placed in the public domain.

if v:version < 700 || &compatible || exists("g:loaded_quickbuf")
    finish
endif
let g:loaded_quickbuf = 1

let g:quickbuf_showbuffs_num_spacing   = get(g:, "quickbuf_showbuffs_num_spacing", 6)
let g:quickbuf_showbuffs_filemod       = get(g:, "quickbuf_showbuffs_filemod"    , ":t")
let g:quickbuf_showbuffs_pathmod       = get(g:, "quickbuf_showbuffs_pathmod"    , ":~:.:h")
let g:quickbuf_showbuffs_noname_str    = get(g:, "quickbuf_showbuffs_noname_str" , "#")
let g:quickbuf_showbuffs_shortenpath   = get(g:, "quickbuf_showbuffs_shortenpath", 0)
let g:quickbuf_switch_to_window        = get(g:, "quickbuf_switch_to_window"     , 0)
let g:quickbuf_line_preview_limit      = get(g:, "quickbuf_line_preview_limit"   , 10)
let g:quickbuf_line_preview_truncate   = get(g:, "quickbuf_line_preview_truncate", 20)
let g:quickbuf_showbuffs_hl_cur        = get(g:, "quickbuf_showbuffs_hl_cur"     , 1)
let g:quickbuf_showbuffs_show_mod      = get(g:, "quickbuf_showbuffs_show_mod"   , 1)

let s:prompt_switchwindowflag = "@"
let s:prompt_string           = " ~!FLAGS!> "

let s:_aliasdata = get(s:, "_aliasdata", {})

let s:_promptdata = {
\ "f_usealias"     : 0,
\ "f_windowswitch" : 0,
\ "f_includenoname": 0,
\ "p_base"         : 0,
\ "p_sanitised"    : 0,
\ "p_isempty"      : 0,
\ "p_flagsonly"    : 0
\ }

let s:flag_regex = {
\ "usealias"     : '^#',
\ "windowswitch" : '^@',
\ "includenoname": '^!'
\ }

let s:flag_display = {
\ "usealias"     : '',
\ "windowswitch" : '@',
\ "includenoname": ''
\ }

function! s:PromptRegenerateData(expr)
    let s:_promptdata['p_base'] = a:expr

    let l:i = match(a:expr, "[a-zA-Z0-9]")
    let s:_promptdata['p_sanitised'] = l:i > -1 ? a:expr[l:i:] : ''
    let s:_promptdata['p_isempty']   = empty(s:_promptdata['p_sanitised'])
    let s:_promptdata['p_flagsonly'] = split( l:i > 0 ? a:expr[:l:i-1] : l:i < 0 ? a:expr : '', '\zs')
    " ~ explanation for ^ ~
    " when text is found, use index-1 to find end of flags in expr
    " when no text found, whole expr must be flags
    " when text is at the beginning of expr (pos 0), then no flags are present

    " determine what flags are active using their regex match
    for f in keys(s:flag_regex)
        let s:_promptdata['f_'.f] = match(s:_promptdata['p_flagsonly'], s:flag_regex[f]) > -1
    endfor

endfunction

function! s:PromptHasFlag(flag)
    return get(s:_promptdata, 'f_'.a:flag, 0)
endfunction

function! s:PromptValue()
    return s:_promptdata['p_sanitised']
endfunction

function! s:PromptIsEmpty()
    return s:_promptdata['p_isempty']
endfunction

function! s:PromptFlagAsString()
    return join(s:_promptdata["p_flagsonly"], '')
endfunction

function! s:_flagstring()
    return join(s:_pd["p_flagsonly"], '')
endfunction

function! s:_createPromptString()
    " TODO create prompt string from flags
endfunction

" function has to be global, otherwise
" the input() autocomplete doesn't find it 
function! Quickbuf_PromptCompletion(A, L, P)
    call s:PromptRegenerateData(a:A)

    if s:PromptHasFlag('usealias')
        let l:vals = s:GetMatchingAliases(s:PromptValue())
    else
        let l:vals = getcompletion(s:PromptValue(), "buffer")
    endif

    " to ensure flags are not removed on tab complete
    let l:flags = s:PromptFlagAsString()
    return map(l:vals, 'l:flags.v:val')

endfunction

function! s:StripWhitespace(line)
    " https://stackoverflow.com/a/4479072
    return substitute(a:line, '^\s*\(.\{-}\)\s*$', '\1', '')
endfunction

function! s:BufferPreview(buf, trunc)
    let l:line = 1
    while 1
        " to stop possible infinite loop
        if l:line > g:quickbuf_line_preview_limit
            return ''
        endif
        try
            let l:str = s:StripWhitespace(getbufline(a:buf, l:line)[0])
        catch /E684/
            return ''
        endtry
        if !empty(l:str)
            break
        endif
        let l:line += 1
    endwhile

    if a:trunc-1 > 0
        if len(l:str) > a:trunc
            return l:str[:a:trunc-1] . '...'
        else
            return l:str[:a:trunc-1]
        endif
    else
        return l:str
    endif
endfunction

function! s:ShowBuffers(bufs, customcount=0)
    " customcount : set to 1 to use counter,
    " or 0 to use bufnums
    if empty(a:bufs)
        return
    endif
    let l:count = 1
    echo "\n"
    for b in a:bufs
        if a:customcount
            let l:num = l:count
        else
            let l:num = b
        endif

        echohl Number
        " highlight current buffer
        let pre_spc = g:quickbuf_showbuffs_num_spacing-len(string(l:num))
        if g:quickbuf_showbuffs_hl_cur && b == bufnr('%')
            echon repeat(" ", l:pre_spc-2)
            echon "> "
        else
            echon repeat(" ", l:pre_spc)
        endif
        echon l:num

        echohl String
        let l:buf = bufname(b)
        echon "  "
        if empty(l:buf)
            echon g:quickbuf_showbuffs_noname_str . b
        else
            echon fnamemodify(l:buf, g:quickbuf_showbuffs_filemod)
        endif
        " show if modified
        if g:quickbuf_showbuffs_show_mod && getbufvar(b, "&mod")
            echon "*"
        endif
        echohl Comment

        echon " : "
        if empty(l:buf)
            let l:path = s:BufferPreview(b, g:quickbuf_line_preview_truncate)
        else
            let l:path = fnamemodify(l:buf, g:quickbuf_showbuffs_pathmod)
            if g:quickbuf_showbuffs_shortenpath
                let l:path = pathshorten(l:path)
            endif
        endif

        echon l:path . "\n"

        echohl None
        let l:count += 1
    endfor
endfunction

function! s:GetMatchingBuffers(expr, limit, allowempty, includenoname=0)
    " allowempty - allow using empty expr to get all listed buffers
    " includenoname - include no name buffers (unsaved/temp files)

    " prioritise active buffer number
    if match(a:expr, "^[0-9]*$") > -1 && a:expr > 0 && bufexists(str2nr(a:expr))
        return [a:expr]
    endif

    let l:bufs = []
    let l:count = 1
    if !empty(a:expr) || a:allowempty
        for b in getcompletion(a:expr, "buffer")
            if l:count > a:limit
                break
            endif
            call add(l:bufs, bufnr(b))
            let l:count += 1
        endfor
    endif

    " include noname buffers
    if a:includenoname && (l:count <= a:limit)
        for b in s:GetEmptyBuffers(a:limit-l:count)
            call add(l:bufs, bufnr(b))
        endfor
    endif

    return l:bufs
endfunction

function! s:GetEmptyBuffers(limit)
    let l:bufs = []
    let l:count = 1
    for b in getbufinfo({'buflisted':1})
        if l:count > a:limit
            break
        endif
        if empty(b.name)
            call add(l:bufs, b.bufnr)
        endif
    endfor
    return l:bufs
endfunction

function! s:GetListSelection(bufs)
    call s:ShowBuffers(a:bufs, 1)
    try
        let l:sel = nr2char(getchar())
        redraw " to fix 'press enter...' msg appearing bug :/
        if empty(matchstr(l:sel, "[A-z0-9]"))
            return
        endif
        if !empty(matchstr(l:sel, "[A-z0]"))
            throw 'append'
        endif
        let l:goto = l:bufs[l:sel-1]
    catch /append\|E684/
        let l:arg = l:sel
    endtry
endfunction

function! s:ShowError(msg)
    echohl ErrorMsg
    echon a:msg
    echohl None
endfunction

function! s:RunPrompt(args)
    let l:pf = ''
    " ^ previous value to use for the prompt (under circumstances)

    " TODO generate prompt string from flags
    let l:prompt = substitute(s:prompt_string, "!FLAGS!",
                \ (g:quickbuf_switch_to_window ? s:prompt_switchwindowflag : ''),
                \ '')
    while 1

        " TODO convert to local instancing of prompt obj rather than one global value
        call s:PromptRegenerateData(input(l:prompt, l:pf, 'customlist,Quickbuf_PromptCompletion'))

        " adding this flag will perform the opposite function of the global
        " switch window setting
        " ie. if switch_window is true, then flag-prompt will not switch windows
        " and not-flag-prompt will switch windows
        let l:canswitch = s:PromptHasFlag('windowswitch') ? !g:quickbuf_switch_to_window : g:quickbuf_switch_to_window

        " exit prompt if no values entered (excluding flags)
        if s:PromptIsEmpty() && !s:PromptHasFlag('includenoname')
            return
        endif

        if s:PromptHasFlag('usealias') && !s:PromptIsEmpty()
            " allow nearest alias matching
            let l:aliasmatches = s:TryGetNearestAliasMatch(s:PromptValue())
            let l:amcount = len(l:aliasmatches)
            if l:amcount == 0
                call s:ShowError("\nalias not found")
                continue
            elseif l:amcount == 1
                call s:ChangeBuffer( s:GetAliasValue(l:aliasmatches[0]), l:canswitch )
                return
            else
                " TODO show selection menu? - inputlist()
                call s:ShowError("\ntoo many alias matches")
                continue
            endif
        endif

        let l:buflist = s:GetMatchingBuffers(s:PromptValue(), 9, 0, s:PromptHasFlag('includenoname'))

        " remove current file
        let l:curf = index(l:buflist, bufnr('%'))
        if l:curf >= 0
            call remove(l:buflist, l:curf)
        endif

        " restart when no buffers found
        if len(l:buflist) == 0
            " do not show error when current file was removed above
            if l:curf >= 0
                return
            endif

            " special case: when whole file name input
            " and no buffer match was found, try changing anyway
            try
                call s:ChangeBuffer( s:PromptValue(), l:canswitch )
                return
            catch /E94\|E86\|E93/
                " TODO may need to handle E93 a little different as its thrown
                " when multiple matching buffers found but all have been deleted
            endtry

            " let l:pf = s:PromptValue()
            call s:ShowError("\nno matches found")
            continue
        " select from buflist when multiple buffers
        elseif len(l:buflist) > 1
            call s:ShowBuffers(l:buflist, 1)

            " buffer selection
            try
                let l:sel = nr2char(getchar())
                redraw " to fix 'press enter...' msg appearing bug :/
                if empty(matchstr(l:sel, "[A-z0-9]"))
                    return
                endif
                if !empty(matchstr(l:sel, "[A-z0]"))
                    throw 'append'
                endif
                let l:buflist = [ l:buflist[l:sel-1] ] " index error
            catch /append\|E684/
                " start new prompt with whatever key was pressed
                let l:pf = l:sel
                continue
            endtry

        endif

        call s:ChangeBuffer( l:buflist[0], l:canswitch )
        return
    endwhile

endfunction

function! s:ChangeBuffer(expr, canswitch=0)
    let l:expr = a:expr

    " if expr is a number, then convert to a number datatype
    " so the window check below functions correctly
    if match(l:expr, "^[0-9]*$") > -1
        let l:expr = str2nr(l:expr)
    endif

    if a:canswitch && !empty(win_findbuf(bufnr(l:expr)))
        " second check makes sure the buffer is open
        " somewhere else (not hidden), otherwise sbuffer command
        " will open a split instead
        " https://stackoverflow.com/questions/10219419/distinguish-between-hidden-and-active-buffers-in-vim
        let l:save = &switchbuf
        set switchbuf=useopen,usetab
        execute 'sbuffer ' . l:expr
        let &switchbuf = l:save
    else
        execute 'buffer ' . l:expr
    endif
endfunction

function! s:HasFlag(expr, flag)
    return (a:expr =~ a:flag)
endfunction

function! s:ClearFlags(...)
    " first arg: string expression
    " remaining args: 1 or more flag regex
    let l:new = a:1
    if a:0 >= 2
        for f in a:000[1:]
            let l:new = substitute(l:new, f, '', '')
        endfor
    endif
    return l:new
endfunction

function! s:ToggleWindowSwitching(...)
    " specific switching can be done through the variable
    let g:quickbuf_switch_to_window = !g:quickbuf_switch_to_window
    echo 'Quickbuf window switch ' . (g:quickbuf_switch_to_window ? 'enabled' : 'disabled')
endfunction

function! s:AddAlias(key, value)
    " only allow aliases to start with a letter
    if match(a:key, "^[a-zA-Z]") == -1
        call s:ShowError("Alias must start with a letter")
        return
    endif

    " since there are no 0 buffer numbers, it can be used as the
    " default no key found
    let l:haskey = get(s:_aliasdata, a:key, 0)
    let s:_aliasdata[a:key] = a:value

    if l:haskey
        echo "Updated alias " . a:key . " from " . l:haskey . " to current buffer"
    else
        echo "Added alias for current buffer as " . a:key
    endif
endfunction

function! s:RemoveAlias(key)
    if a:key == "*"
        if confirm("Delete all aliases?", "&Yes\n&No", 2) == 1
            let s:_aliasdata = {}
            echo "Removed all aliases"
        endif
        return
    endif

    if has_key(s:_aliasdata, a:key)
        unlet s:_aliasdata[a:key]
        echo "Removed alias " . a:key
    else
        echo "Alias " . a:key . " not found"
    endif
endfunction

function! s:GetAliasValue(key, allowcreate=0)
    " TODO probably remove this (abandoned functionality)
    if a:allowcreate
        if !has_key(s:_aliasdata, a:key) && confirm("Alias " . a:key . " does not exist. Create a new?", "&Yes\n&No", 2) == 1
            s:AddAlias(a:key, bufnr())
        else
            throw 'notfound'
        endif
    endif
    return s:_aliasdata[a:key]
endfunction

" https://vi.stackexchange.com/a/13590
function! s:GetMatchingAliases(A, ...)
    return filter(keys(s:_aliasdata), 'v:val =~ "^' . a:A .'"')
endfunction

" similar to GetMatchingAliases but
" does not allow empty expr
" if exact key, match returns it only
function! s:TryGetNearestAliasMatch(expr)
    if empty(a:expr)
        return []
    elseif has_key(s:_aliasdata, a:expr)
        return [a:expr]
    else
        return s:GetMatchingAliases(a:expr)
    endif
endfunction

function! s:ListBuffersCommand(expr)
    call s:PromptRegenerateData(a:expr)
    call s:ShowBuffers(s:GetMatchingBuffers(s:PromptValue(), 999, 1, s:PromptHasFlag('includenoname')), 0)
endfunction

command! -nargs=? QBPrompt call s:RunPrompt(<q-args>)
command! -nargs=? QBList call s:ListBuffersCommand(<q-args>)
command! -nargs=? QBWindowSwitchToggle call s:ToggleWindowSwitching(<q-args>)
command! -nargs=1 QBAddAlias call s:AddAlias(<q-args>, bufnr())
command! -nargs=1 -complete=customlist,s:GetMatchingAliases QBRemoveAlias call s:RemoveAlias(<q-args>)


