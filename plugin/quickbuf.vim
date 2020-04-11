"
" *QuickBuf* Creates a prompt to allow for quick
"   \ and non-intrusive buffer switching
" Author:      Jaspreet Panesar <jaspreetpanesar>
" Version:     1.0
" Last Change: 2020 Mar 07
" Licence:     This file is placed in the public domain.

if v:version < 700 || &compatible || exists("g:loaded_quickbuf")
    finish
endif
let g:loaded_quickbuf = 1


let g:quickbuf_showbuffs_num_spacing = get(g:, "quickbuf_showbuffs_num_spacing", 5)
let g:quickbuf_showbuffs_filemod     = get(g:, "quickbuf_showbuffs_filemod", ":t")
let g:quickbuf_showbuffs_pathmod     = get(g:, "quickbuf_showbuffs_pathmod", ":~:.:h")
let g:quickbuf_prompt_string         = get(g:, "quickbuf_prompt_string", " ~> ")
let g:quickbuf_showbuffs_shortenpath = get(g:, "quickbuf_showbuffs_shortenpath", 0)
let g:quickbuf_prompt_version        = get(g:, "quickbuf_prompt_version", 2)

function s:ShowBuffers(bufs, customcount)
    " customcount used to specify whether to use bufnum or counter
    if empty(a:bufs)
        return
    endif
    let l:count = 1
    echo "\n"
    for b in a:bufs
        if a:customcount
            let l:num = l:count
        else
            let l:num = bufnr(b)
        endif
        echon repeat(" ", g:quickbuf_showbuffs_num_spacing-len(string(l:num)))
        echohl Number
        echon l:num
        echohl String
        echon "  " . fnamemodify(b, g:quickbuf_showbuffs_filemod)
        echohl NonText

        let l:path = fnamemodify(b, g:quickbuf_showbuffs_pathmod)
        if g:quickbuf_showbuffs_shortenpath
            let l:path = pathshorten(l:path)
        endif
        echon " : " . l:path . "\n"

        echohl None
        let l:count += 1
    endfor
endfunction

function s:GetMatchingBuffers(expr, limit)
    let l:bufs = []
    let l:count = 1
    for b in getcompletion(a:expr, "buffer")
        if l:count > a:limit
            break
        endif
        call add(l:bufs, fnamemodify(b, ":p"))
        let l:count += 1
    endfor
    return l:bufs
endfunction

function s:RunPrompt_v1(arg)
    let l:goto = ""
    let l:arg = a:arg

    if !empty(l:arg)
        let l:bufs = s:GetMatchingBuffers(l:arg, 9)

        " remove current file from buf list
        let l:curr = index(l:bufs, expand("%:p"))
        if l:curr >= 0
            call remove(l:bufs, l:curr)
        endif

        " if single file in buf list, auto switch to it
        if len(l:bufs) == 1
            let l:goto = l:bufs[0]

        " show buf list / selection prompt
        elseif len(l:bufs) > 1
            call s:ShowBuffers(l:bufs, 1)
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
        endif
    endif

    " seperate check to allow arg appending after no index selection
    if empty(l:goto)
        let l:goto = input(g:quickbuf_prompt_string, l:arg, "buffer")
        if empty(l:goto)
            return
        endif
    endif

    try
        execute 'buffer ' . l:goto
    " multiple matches
    catch /E93/
        call s:RunPrompt(l:goto)
    " no matches
    catch /E94/
        echohl ErrorMsg
        echon "\nno matches found"
        echohl None
        call s:RunPrompt("")
    endtry
endfunction

function s:GetListSelection(bufs)
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

function s:ShowError(msg)
    echohl ErrorMsg
    echon a:msg
    echohl None
endfunction

function s:RunPrompt_v2(args)
    let l:pf = ''
    while 1
        let l:goto = input(g:quickbuf_prompt_string, l:pf, "buffer")

        if empty(l:goto) 
            return
        endif

        let l:buflist = []
        " TODO allow reading noname buffers
        if 0
        else
            let l:buflist = s:GetMatchingBuffers(l:goto, 9)
        endtry

        " remove current file
        let l:curf = index(l:buflist, expand("%:p"))
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
                call s:ChangeBuffer( l:goto )
                return
            catch /E94/
                " no matches
            endtry

            let l:pf = l:goto
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

        call s:ChangeBuffer( l:buflist[0] )
        return
    endwhile

endfunction

function s:ChangeBuffer(expr)
    execute 'buffer ' . a:expr
endfunction

function s:RunPrompt(args)
    if g:quickbuf_prompt_version == 1
        call s:RunPrompt_v1(a:args)
    else
        call s:RunPrompt_v2(a:args)
    endif
endfunction


command! -nargs=? QBPrompt call s:RunPrompt(<q-args>)
command! -nargs=? QBList call s:ShowBuffers(getcompletion(<q-args>, "buffer"), 0)


