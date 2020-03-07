
" quickbuf.vim
" Author: Jaspreet Panesar <jaspreetpanesar>
" Version: 0.0.0
" Last Change: 2020 Mar 07
" Licence: This file is placed in the public domain.

" Credits:
" <stackoverflow links>


if v:version < 700
    echoerr "~This belongs in a museum!\nupdate your vim to >= version 7.00"
endif

if exists("loaded_quickbuff")
    finish
endif
let g:loaded_quickbuff = 1


" TODO
" User Customisation:
"   1. buffer list colours (number, file, path),
"   2. buffer list format (file, path),
"   3. prompt (custom string, or function), 
" Functions:
"   1. show buffers
"   2. change buffer
"   3. get matching buffers

let g:quickbuff_showbuffs_num_spacing = 5
let g:quickbuff_showbuffs_filemod = ":t"
let g:quickbuff_showbuffs_pathmod = ":~:.:h"

function s:ShowBuffer(bufs, customcount)
    " error catching
    if empty(a:bufs)
        return
    endif

    " show buffers
    let l:count = 1
    echo "\n"
    for b in a:bufs
        try
            if (a:customcount) 
                let l:n = l:count
            else
                let l:n = bufnr(b)

            " to align numbers
            echon repeat(" ", g:quickbuff_showbuffs_num_spacing-len(string(l:num)))

            echohl Number
            echon l:n
            echohl String
            echon "  " . fnamemodify(b, ":t")
            echohl NonText
            echon " : " . fnamemodify(b, ":~:.:h") . "\n"
            echohl None

           let l:count += 1 
        catch
            echoerr "an error occured"
        endtry
    endfor
endfunction





