
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

Prepend search pattern with `!` to view/switch to no-name buffers.

Display all buffers matching pattern (uses vim's own buffer completion):
```
:QBList <pattern>
```

## Planned
> finish the read me :P


