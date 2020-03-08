
# vim-quickbuf
Allow for quick, and non-intrusive buffer switching through a custom prompt.

> add gif showing usage

## Installation
Use a plugin manager (eg. Vundle). Requires Vim version > 7
```
Plugin 'jaspreetpanesar/vim-quickbuf'
```

## Usage
Run using command:
```
:QBPrompt
```

Map command for faster usage (my personal recommendation is double tap leader key)
```
nnoremap <leader><leader> :QBPrompt<cr>
```

## Customisation
See `:h quickbuf` for more information

*Buffer prompt*
- Static prompt string: `g:quickbuf_prompt_string`
- Dynamic prompt string using function : `g:quickbuf_prompt_function`

*File display*
- Path display format: `g:quickbuf_showbuffs_pathmod`
- File display format: `g:quickbuf_showbuffs_filemod`
- Shorten file path: `g:quickbuf_showbuffs_shortenpath`
- Buffer index alignment: `g:quickbuf_showbuffs_num_spacing`

## Extra
Display all buffers matching pattern (uses vim's own buffer completion):
```
:QBList <pattern>
```

## Planned
> finish the read me :P


