vim9script

# ---------------------------------------------------------------------------- #
#
#  Statusline with vim9-focalpoint
#
#  Source this file to see the vim9-focalpoint statusline plugin at work.
#
# ---------------------------------------------------------------------------- #

set laststatus=2

# default values for config variables. No need to include these unless you
# want to change them.
# g:focalpoint_cn_candidates = ['IncSearch', 'Search', 'ErrorMsg']
# g:focalpoint_text_fade = 0.65
# g:focalpoint_bg_fade = 0.1

def g:GenerateStatusline(winid: number): string
    # build a statusline string using vim9-focalpoint
    
    var stl = ""

    # g:FPHiSelect chooses a highlight group based on winid
    var hi_group = g:FPHiSelect(winid, 'StatusLine', 'StatusLineNC', 'StatusLineCN')

    # g:FPSelect chooses a string based on winid
    var state = g:FPSelect(winid, 'STATUS LINE', 'NOT CURRENT', 'CURRENT NOW')

    # set your highlighting
    stl ..= hi_group

    # show the state, to help show what is going on
    stl ..= ' ' .. state .. ' --->'

    # show a few of the usual items
    stl ..= ' %f %h%w%m%r %=%(%l,%c%V %= %P%'

    return stl
enddef

set statusline=%!GenerateStatusline(g:statusline_winid)

# comment this out to remove window shading
augroup ShadeNotCurrentWindow
  autocmd!
  autocmd WinEnter * setl wincolor=Normal
  autocmd WinLeave * setl wincolor=NormalNC
augroup END

# refresh highlight and lowlight colors when you switch colorshcemes
augroup ResetStatuslineHiGroups
  autocmd!
  autocmd colorscheme * g:FPReset()
augroup END

# use Pmenu to shade unfocused windows for these colorschemes
g:use_pmenu_to_shade = [
    'delek',
    'habamax',
    'industry',
    'koehler',
    'lunaperche',
    'morning',
    'pablo',
    'peachpuff',
    'quiet',
    'retrobox',
    'torte',
    'wildcharm',
]

augroup ResetStatuslineHiGroups
  autocmd!
  autocmd colorscheme * g:focalpoint_use_pmenu = index(g:use_pmenu_to_shade, g:colors_name) != -1 ? v:true : v:false | g:FPReset()
augroup END
