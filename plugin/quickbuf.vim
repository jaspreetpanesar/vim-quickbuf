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
let g:quickbuf_showbuffs_filemod       = get(g:, "quickbuf_showbuffs_filemod", ":t")
let g:quickbuf_showbuffs_pathmod       = get(g:, "quickbuf_showbuffs_pathmod", ":~:.:h")
let g:quickbuf_showbuffs_noname_str    = get(g:, "quickbuf_showbuffs_noname_str", "#")
let g:quickbuf_prompt_string           = get(g:, "quickbuf_prompt_string", " ~!FLAGS!> ")
let g:quickbuf_prompt_switchwindowflag = get(g:, "quickbuf_prompt_switchwindowflag", "#")
let g:quickbuf_showbuffs_shortenpath   = get(g:, "quickbuf_showbuffs_shortenpath", 0)
let g:quickbuf_switch_to_window        = get(g:, "quickbuf_switch_to_window", 0)
let g:quickbuf_line_preview_limit      = get(g:, "quickbuf_line_preview_limit", 10)
let g:quickbuf_line_preview_truncate   = get(g:, "quickbuf_line_preview_truncate", 20)
let g:quickbuf_include_noname_regex    = get(g:, "quickbuf_include_noname_regex", "^!")
let g:quickbuf_switchtowindow_regex    = get(g:, "quickbuf_switchtowindow_regex", "^@")
let g:quickbuf_usealias_regex          = get(g:, "quickbuf_usealias_regex", "^#")
let g:quickbuf_showbuffs_hl_cur        = get(g:, "quickbuf_showbuffs_hl_cur", 1)
let g:quickbuf_showbuffs_show_mod      = get(g:, "quickbuf_showbuffs_show_mod", 1)

let s:alias_list = get(s:, "alias_list", {})

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

function! s:ShowBuffers(bufs, customcount)
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
    let l:expr = substitute(a:expr, g:quickbuf_include_noname_regex, '', '')

    " prioritise active buffer number
    if match(l:expr, "^[0-9]*$") > -1 && l:expr > 0 && bufexists(str2nr(l:expr))
        return [l:expr]
    endif

    let l:bufs = []
    let l:count = 1
    if !empty(l:expr) || a:allowempty
        for b in getcompletion(l:expr, "buffer")
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
    " generate prompt string from flags
    let l:prompt = substitute(g:quickbuf_prompt_string, "!FLAGS!",
                \ (g:quickbuf_switch_to_window ? g:quickbuf_prompt_switchwindowflag : ''),
                \ '')
    while 1
        let l:goto = input(l:prompt, l:pf, "buffer")

        if empty(l:goto) 
            return
        endif

        " determine attributes then remove them from input
        " TODO cleaner way to remove flags

        let l:usealias = s:HasFlag(l:goto, g:quickbuf_usealias_regex)
        let l:goto = s:ClearFlags(l:goto, g:quickbuf_usealias_regex)

        " TODO handle window switching flag too
        if l:usealias
            if has_key(s:alias_list, l:goto)
                call s:ChangeBuffer(s:alias_list[l:goto])
            else
                call s:ShowError("\nAlias not found")
            endif
            return
        endif

        let l:includenoname = s:HasFlag(l:goto, g:quickbuf_include_noname_regex)
        let l:goto = s:ClearFlags(l:goto, g:quickbuf_include_noname_regex)

        " adding this flag will perform the opposite function of the global
        " switch window setting
        " ie. if switch_window is true, then flag-prompt will not switch windows
        " and not-flag-prompt will switch windows
        let l:canswitch = s:HasFlag(l:goto, g:quickbuf_switchtowindow_regex) ? !g:quickbuf_switch_to_window : g:quickbuf_switch_to_window
        let l:goto = s:ClearFlags(l:goto, g:quickbuf_switchtowindow_regex)

        let l:buflist = s:GetMatchingBuffers(l:goto, 9, 0, l:includenoname)

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
                call s:ChangeBuffer( l:goto, l:canswitch )
                return
            catch /E94\|E86\|E93/
                " TODO may need to handle E93 a little different as its thrown
                " when multiple matching buffers found but all have been deleted
            endtry

            " let l:pf = l:goto
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
    let s:alias_list[a:key] = a:value
    echo "Added alias for current buffer as " . a:key
endfunction

function! s:RemoveAlias(key)
    if has_key(s:alias_list, a:key)
        unlet s:alias_list[a:key]
        echo "Removed alias " . a:key
    else
        echo "Alias " . a:key . " not found"
    endif
endfunction

" https://vi.stackexchange.com/a/13590
function! s:GetMatchingAliases(ArgLead, CmdLine, CursorPos)
    return filter(keys(s:alias_list), 'v:val =~ "^' . a:ArgLead .'"')
endfunction


command! -nargs=? QBPrompt call s:RunPrompt(<q-args>)
command! -nargs=? QBList call s:ShowBuffers(s:GetMatchingBuffers(s:ClearFlags(<q-args>, g:quickbuf_include_noname_regex), 999, 1, s:HasFlag(<q-args>, g:quickbuf_include_noname_regex)), 0)
command! -nargs=? QBWindowSwitch call s:ToggleWindowSwitching(<q-args>)
command! -nargs=1 QBAddAlias call s:AddAlias(<q-args>, bufnr())
command! -nargs=1 -complete=customlist,s:GetMatchingAliases QBRemoveAlias call s:RemoveAlias(<q-args>)


