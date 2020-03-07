
" quickbuf.vim
" Author: Jaspreet Panesar <jaspreetpanesar>
" Version: 0.0.0
" Last Change: 2020 Mar 07
" Licence: This file is placed in the public domain.

" Credits:
" <stackoverflow links>

if v:version < 700 || &compatible || exists("g:loaded_quickbuf")
    finish
endif
let g:loaded_quickbuf = 1

" TODO
" add prompt customisation through function
" update prompt function to not use recursive calls
" add comments
" implement pathshorten() for show buffers

let g:quickbuf_showbuffs_num_spacing = get(g:, "quickbuf_showbuffs_num_spacing", 5)
let g:quickbuf_showbuffs_filemod     = get(g:, "quickbuf_showbuffs_filemod", ":t")
let g:quickbuf_showbuffs_pathmod     = get(g:, "quickbuf_showbuffs_pathmod", ":~:.:h")
let g:quickbuf_prompt_string         = get(g:, "quickbuf_prompt_string", " ~> ")
let g:quickbuf_showbuffs_shortenpath = get(g:, "quickbuf_showbuffs_shortenpath", 0)

function s:ShowBuffers(bufs, customcount)
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

        if g:quickbuf_showbuffs_shortenpath
            let l:path = pathshorten(fnamemodify(b, g:quickbuf_showbuffs_pathmod))
        else
            let l:path = fnamemodify(b, g:quickbuf_showbuffs_pathmod)
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

function s:RunPrompt(arg)
    let l:goto = ""
    let l:arg = a:arg

    if !empty(l:arg)
        let l:bufs = s:GetMatchingBuffers(l:arg, 9)
        if len(l:bufs) == 1
            let l:goto = l:bufs[0]
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

command! -nargs=? QBPrompt call s:RunPrompt(<q-args>)
command! -nargs=? QBList call s:ShowBuffers(getcompletion(<q-args>, "buffer"), 0)


