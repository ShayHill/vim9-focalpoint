vim9script
# ---------------------------------------------------------------------------- #
#
# StatusLineNC
#
# Statuslines in Vim are by default highlighted with the StatusLine and
# StatusLineNC (StatusLine Not Current) highlight groups. When no splits are
# open, you will only see the StatusLine highlight group. When splits are
# open, the focused split will have the StatusLine highlight and unfocused
# splits will have the StatusLineNC highlight.
#
# Often, I would prefer more contrast between these groups, so this module
# creates a third highlighting group for statuslines, StatusLineCN (StatusLine
# Current Now). When/no splits are open, you will only see the StatusLine
# highlight group (a nice, coordinating color as the colorscheme designer
# intended it). When splits are open, the focused split will have the
# high-contrast StatusLineCN highlight and unfocused splits will have the
# StatusLineNC highlight.
#
# That part is simple. A lot of the code here is for the secondary functions
# of highlighting and lowlighting text against a background. The main purpose
# *is* to create a new StatusLineCN highlight group, but the module actually
# creates 8 new highlight groups for a total of 9 StatusLine highlight groups
# and 2 background highlight groups.
#
# * StatusLineHard (bold text for default statusline)
# * StatusLine  " previously existing
# * StatusLineSoft (grayed out text for default statusline)
# * StatusLineNCHard (bold text unfocused statusline)
# * StatusLineNC  " previously existing
# * StatusLineNCSoft (grayed out text for default statusline)
# * StatusLineCNHard (bold text for focused statusline with splits)
# * StatusLineCN  (normal text for focused statusline with splits)
# * StatusLineSoft (grayed out test for focused statusline with splits)
# * Normal  " previously existing
# * NormalNC (Normal with a faded background color)
#
# ---------------------------------------------------------------------------- #

v:errors = []

# Try to get at least this much squared Euclidean distance between the color
# of the 'Current Now' statusline and the 'Not Current' (StatusLineNC)
# statusline. If no candidate is found that meets this criterion, use the
# candidate with the best squared Euclidean distance from StatusLineNC.
const SUFFICIENT_CONTRAST = 16000

# The high-contrast StatusLineNC highlight is selected from high-contrast
# highlight groups in the current colorscheme. These are the candidates in
# order of preference.
if !exists('g:focalpoint_cn_candidates')
    g:focalpoint_cn_candidates = ['IncSearch', 'Search', 'ErrorMsg']
endif

g:focalpoint_text_fade = .65
if !exists('g:focalpoint_text_fade')
    g:focalpoint_text_fade = 0.65
endif

if !exists('g:focalpoint_bg_fade')
    g:focalpoint_bg_fade = 0.1
endif

if !exists('g:focalpoint_use_pmenu')
    g:focalpoint_use_pmenu = v:true
endif


# ---------------------------------------------------------------------------- #
#
# Color Math
#
# ---------------------------------------------------------------------------- #

def HexToRgb(hex_color: string): list<number>
    # convert a color in 16bit hex notation (e.g., '#ffffff') to three 16-bit
    # integers
    var red = str2nr('0x' .. strpart(hex_color, 1, 2), 16)
    var green = str2nr('0x' .. strpart(hex_color, 3, 2), 16)
    var blue = str2nr('0x' .. strpart(hex_color, 5, 2), 16)
    return [red, green, blue]
enddef


def RgbToHex(rgb: list<number>): string
    # Convert three floats [0 .. 255] to a 16-bit color hex string (e.g.,
    # '#ffffff')
    var three_hex = map(copy(rgb), (_, v) => printf('%02x', v))
    return '#' .. join(three_hex, '')
enddef


def ValueToColorIndex(v: number): number
    # Strength of color value [0 .. 5].
    # Subroutine of HexToCterm
    #
    # Inputs:
    #   v - [0 .. 255]
    # Returns:
    #   [0 .. 5]
    #
    # Red identifies a subset of the cterm colors [16 .. 231]
    # Green identifies a subset of that subset
    # Blue idenfities a member of *that* subset
    if v < 48
        return 0
    elseif v < 115
        return 1
    else
        return (v - 35) / 40
    endif
enddef


def SqEuclidean(vec_a: list<number>, vec_b: list<number>): number
    # Squared Euclidean distance between two vectors
    var diffs = map(copy(vec_a), (i, v) => v - vec_b[i]) 
    var terms = map(copy(diffs), (_, v) => v * v)
    return terms[0] + terms[1] + terms[2]
enddef


def SqColorSpan(hex_color_a: string, hex_color_b: string): number
    # Squared distance between two colors in the RGB color space
    #
    # Inputs:
    #   hex_color_a - '#ffffff'
    #   hex_color_b - '#000000'
    # Returns:
    #   [0 .. 195075]
    #
    # This is only useful for determining < = > relationships between pairs of
    # colors.
    var rgb_a = HexToRgb(hex_color_a)
    var rgb_b = HexToRgb(hex_color_b)
    return SqEuclidean(rgb_a, rgb_b)
enddef


if assert_equal(SqEuclidean([0, 0, 1], [0, 0, 0]), 1) | throw v:errors[-1] | endif
if assert_equal(SqEuclidean([255, 0, 0], [0, 0, 0]), 65025) | throw v:errors[-1] | endif


def HexToCterm(hex_color: string): string
    # The nearest cterm color to a hex color
    # This is apparently the algorithm used by tmux, but it won't necessarily
    # produce the same result as a brute force check. Definitely close enough
    # and a lot faster.
    #
    # Returns
    #   [16 .. 255] 1-15 (user-defined colors) are ignored
    var rgb = HexToRgb(hex_color)
    var [red, g, blue] = HexToRgb(hex_color)

    # nearest xterm color [0 .. 215] => [16 .. 231]
    var [ir, ig, ib] = map(copy(rgb), (_, v): number => ValueToColorIndex(v))
    var color_index = 36 * ir + 6 * ig + ib

    # nearest xterm grayscale [0 .. 23] => [232 .. 255]
    var average = (rgb[0] + rgb[1] + rgb[2]) / 3
    var gray_index = average > 238 ? 23 : (average - 3) / 10

    # Calculate the represented colors back from the indices
    var i2cv = [0, 0x5f, 0x87, 0xaf, 0xd7, 0xff]
    var cterm_color = map([ir, ig, ib], (_, v) => i2cv[v])
    var [cr, cg, cb] = cterm_color  # [[0 .. 255], [0 .. 255], [0 .. 255]]
    var gv = 8 + 10 * gray_index  # [0 .. 255]

    var gray_err = SqEuclidean(rgb, [gv, gv, gv])
    var color_err = SqEuclidean(rgb, cterm_color)
    return color_err <= gray_err ? string(16 + color_index) : string(232 + gray_index)
enddef


# The first 16 terminal colors (If the user hasn't changed them).
const TERM_COLORS = [
    '#000000', '#800000', '#008000', '#808000',
    '#000080', '#800080', '#008080', '#c0c0c0',
    '#808080', '#ff0000', '#00ff00', '#ffff00',
    '#0000ff', '#ff00ff', '#00ffff', '#ffffff'
]


def CtermToHex(cterm_color: string): string
    # An inverse of the transformation in HexToCterm. Not the same result as a
    # simple map, but keeping consistent with Hex2Cterm.
    var num = str2nr(cterm_color)
    if num == 0 && cterm_color != '0'
        throw 'Cannot create hex color from ' .. cterm_color
    endif
    if num < 16
        return TERM_COLORS[num]
    endif

    if num > 231
        var gray = 23 - (255 - num)
        gray = gray * 10 + 8
        return RgbToHex([gray, gray, gray])
    endif

    var rem = num - 16
    var red = rem / 36
    rem = rem % 36
    var grn = rem / 6
    var blu = rem % 6
    var i2cv = [0, 0x5f, 0x87, 0xaf, 0xd7, 0xff]
    return RgbToHex(map([red, grn, blu], (_, v) => i2cv[v]))
enddef


def TryHex(color: string): string
    # Try to get a hex color from one of the (too) many color arguments Vim
    # allows. Return '' if failed.
    # Inputs:
    #   color - [0 .. 255] as a string
    # Returns:
    #   given ['0' .. '255'] - a hex-color value for a cterm index
    #   given '#ffffff' - '#ffffff'
    #   given 'red' = '#ff0000'
    #   given 'Red' = '#ff0000'
    #   given '' or invalid input = ''
    var hex: string

    # if color arg is already a hex string
    if len(color) == 7 && color[0] == '#' | return color | endif

    # if color arg is an empty string
    if color == '' | return '' | endif

    # try color arg as a [0 .. 255] palette index
    try
        hex = CtermToHex(color)
    catch /Cannot create hex color from/
        hex = ''
    endtry

    # try color arg as a key in v:colornames dict
    if hex == '' | hex = v:colornames->get(tolower(color), '') | endif

    return hex
enddef

if assert_equal(TryHex('#ffffff'), '#ffffff') | throw v:errors[-1] | endif
if assert_equal(TryHex('0'), TERM_COLORS[0]) | throw v:errors[-1] | endif
if assert_equal(TryHex(''), '') | throw v:errors[-1] | endif
if assert_equal(TryHex('garbage'), '') | throw v:errors[-1] | endif
if assert_equal(TryHex('Red'), '#ff0000') | throw v:errors[-1] | endif
if assert_equal(TryHex('White'), '#ffffff') | throw v:errors[-1] | endif


def MixColors(hex_color_a: string, hex_color_b: string, ratio: float): string
    # Mix two hex colors.
    var rgb_a = HexToRgb(hex_color_a)
    var rgb_b = HexToRgb(hex_color_b)
    var mixed = map(copy(rgb_a), (i, v): float => v * ratio + rgb_b[i] * (1 - ratio))
    return RgbToHex(map(mixed, (_, v) => float2nr(v)))
enddef


# ---------------------------------------------------------------------------- #
#
# Identify fg and bg colors in existing highlight groups
#
# ---------------------------------------------------------------------------- #

def HlgetOrEmpty(hi_group: string): dict<any>
    # Get a highlight group dictionary. If the highlight group does not exist,
    # return an empty dictionary.
    var hi_dict: dict<any>
    try
        hi_dict = hlget(hi_group, v:true)[0]
    catch /^Vim\%((\a\+)\)\=:E684:/
        hi_dict = {}
    endtry
    return hi_dict
enddef

if assert_equal(HlgetOrEmpty('DoesNotExist'), {}) | throw v:errors[-1] | endif

def HiFgOrBg(sources: list<string>, fg_or_bg: string): dict<string>
    # Get either the fg or bg colors from the first viable candidate in a list
    # of sources. Search order is.
    # * if the first source has both guifg and ctermfg, return both
    # * if the first source has one of guifg or ctermfg, match them as
    #   closely as possible
    # * if the first source has neigher guifg or ctermfg, move to the next
    #   source
    # * if all sources are exhausted AND the last source provided was
    #   'Normal', return black for the foreground or white for the background.
    #
    # Inputs:
    #  sources: list of highlight group names 
    #  fg_or_bg: 'fg' or 'bg'
    #
    # Returns:
    #   dict with keys ['guifg' and 'ctermfg'] or ['guibg' and 'ctermbg']. Each
    #   mapped to a hex color.
    #
    # I call this two ways:
    # 1. [some_group, ..., 'Normal'] - This means 'give me *some* foreground
    #   or background color no matter what'. Some of the Vim themes provide
    #   *nothing*, just instructions or flags like 'cleared'. If 'Normal' is
    #   passed as the last source and the Normal highlight group is 'cleared',
    #   just return black and white.
    # 2. [some_group] - This means 'give me a fg or bg if it's there, else an
    #   empty string'.
    var gui_g: string
    var cterm_g: string
    var gui_attr = 'gui' .. fg_or_bg
    var cterm_attr = 'cterm' .. fg_or_bg

    def RecurHiFgOrBg(hlgs: list<string>): dict<string>
        var hidict = HlgetOrEmpty(hlgs[0])
        gui_g = TryHex(hidict->get(gui_attr, ''))
        cterm_g = TryHex(hidict->get(cterm_attr, ''))
        gui_g = gui_g != '' ? gui_g : cterm_g
        cterm_g = cterm_g != '' ? cterm_g : gui_g

        if gui_g != ''
            return {gui: gui_g, cterm: cterm_g}
        endif

        if len(hlgs) == 1
            var default: string
            if hlgs[0] == 'Normal'
                default = fg_or_bg == 'fg' ? '#000000' : '#ffffff'
            else
                default = ''
            endif
            return {gui: default, cterm: default}
        endif

        return RecurHiFgOrBg(hlgs[1 : ])
    enddef

    return RecurHiFgOrBg(sources)
enddef


def HiGrounds(sources: list<string>): dict<string>
    # Get **display** guifg, guibg, ctermfg, and ctermbg from the first viable
    # source in sources. The **display** part is important. Often, a highlight
    # group contains the instruction `gui=reverse` or `cterm=reverse`. In
    # those cases, this function will return the bg color for guifg and the fg
    # color for guibg. This can get confusing, because when these colors are
    # eventually reassigned to other highlight groups, you may be setting the
    # explicit (exactly as stated in the highlight group) guibg with the
    # **display** guifg.

    var source = HlgetOrEmpty(sources[0])
    var is_gui_reversed = source->get('gui', {})->get('reverse', v:false)
    var is_cterm_reversed = source->get('cterm', {})->get('reverse', v:false)

    var fgs = HiFgOrBg(sources, 'fg')
    var bgs = HiFgOrBg(sources, 'bg')

    if fgs.gui == '' || fgs.cterm == '' || bgs.gui == '' || bgs.cterm == ''
        # echo "cannot find background for " .. sources[0]
    endif

    return {
        guifg: is_gui_reversed ? bgs.gui : fgs.gui,
        guibg: is_gui_reversed ? fgs.gui : bgs.gui,
        ctermfg: is_cterm_reversed ? bgs.cterm : fgs.cterm,
        ctermbg: is_cterm_reversed ? fgs.cterm : bgs.cterm,
    }
enddef


# ---------------------------------------------------------------------------- #
#
# Create new highlight groups
#
# ---------------------------------------------------------------------------- #

def HardHi(base_hi_group: string, basename: string = ''): void
    # Create an emphasized version of a highlight group.
    # 
    # Inputs:
    #   base_hi_group - highlight group from which to inherit default values
    #   basename - optionally pass a basename for the new highlight group, if
    #     no basename is given, a new group `base_hi_group .. 'Hard'` will be
    #     created.
    # Effects:
    #  Creates a new highlight group which should be an emphasized version of
    #  the input highlight group
    var hldict = HlgetOrEmpty(base_hi_group)
    hldict.name = basename == '' ? base_hi_group .. 'Hard' : basename .. 'Hard'

    # make text bold
    hldict.gui = hldict->get('gui', {})->extend({ bold: v:true })
    hldict.term = hldict->get('term', {})->extend({ bold: v:true })
    hldict.cterm = hldict->get('cterm', {})->extend({ bold: v:true })
    hlset([hldict])
enddef


def SoftHi(base_hi_group: string, basename: string = ''): void
    # Create a de-emphasized version of a highlight group.
    # 
    # Inputs:
    #   base_hi_group - highlight group from which to inherit default values
    #   basename - optionally pass a basename for the new highlight group, if
    #     no basename is given, a new group `base_hi_group .. 'Soft'` will be
    #     created.
    # Effects:
    #  Creates a new highlight group which should be an emphasized version of
    #  the input highlight group
    var hldict = hlget(base_hi_group, v:true)[0]
    hldict.name = basename == '' ? base_hi_group .. 'Soft' : basename .. 'Soft'

    # if anything surprising happens, hi group will still exist, but will be
    # an exact match for base_hi_group
    hlset([hldict])
    var grounds = HiGrounds([base_hi_group, 'Normal'])
    if grounds.guifg == '' || grounds.ctermfg == ''
        return
    endif

    var gui_mixed = MixColors(grounds.guibg, grounds.guifg, g:focalpoint_text_fade)
    if hldict->get('gui', {})->get('reverse', v:false)
        hldict.guibg = gui_mixed
    else
        hldict.guifg = gui_mixed
    endif

    var cterm_mixed = MixColors(grounds.ctermbg, grounds.ctermfg, g:focalpoint_text_fade)
    cterm_mixed = HexToCterm(cterm_mixed)
    if hldict->get('cterm', {})->get('reverse', v:false)
        hldict.ctermbg = cterm_mixed
    else
        hldict.ctermfg = cterm_mixed
    endif

    hlset([hldict])
enddef


def PickCurrentNowHi(candidates: list<string>): string
    # Search the highlight group candidates for a candidate with sufficient
    # background contrast with StatusLineNC. If no candidate with sufficient
    # contrast is found, return the best candidate.
    #
    # Unexpected things that could cause this to fail
    # - StatusLineNC is not defined (this is a default highlight group, so it
    #   should always exist)
    # - None of the candidates exist
    # - No candidates are provided
    # - None of the candidates has a background color
    #
    # If one of these or any other problem occurs, just return 'StatusLine',
    # the default statusline hightlight group.
    try
        var statusline_nc_bg = HiGrounds(['StatusLineNC', 'Normal']).guibg
        var contrast: number
        var guibg: string
        var best_contrast = 0
        var best_candidate = candidates[0]

        for candidate in candidates
            guibg = HiGrounds([candidate]).guibg
            if guibg == '' | continue | endif

            contrast = SqColorSpan(statusline_nc_bg, guibg)
            if contrast > SUFFICIENT_CONTRAST
                return candidate
            endif
            if contrast > best_contrast
                best_contrast = contrast
                best_candidate = candidate
            endif
        endfor

        if best_contrast == 0
            return 'StatusLine'
        endif
        return best_candidate
    catch
        return 'StatusLine'
    endtry
enddef


def SplitHi(hi_group: string, basename: string = ''): void
    # Split a highlight group into three.
    # * base
    # * baseHard
    # * baseSoft
    #
    # Inputs:
    #   hi_group - name of an existing highlight group
    #   basename - optional basename for new highlight groups
    #
    # If a basename is given
    # * create basename identical to hi_group
    # * create basename .. 'Hard' from hi_group
    # * create basename .. 'Soft' from hi_group
    #
    # If no basename is given
    # * create hi_group .. 'Hard' from hi_group
    # * create hi_group .. 'Soft' from hi_group
    if basename == ''
        HardHi(hi_group)
        SoftHi(hi_group)
        return
    endif
    var hldict = hlget(hi_group, v:true)[0]
    hldict.name = basename
    hlset([hldict])
    HardHi(hi_group, basename)
    SoftHi(hi_group, basename)
enddef


def DefineNormalNC(): void
    # Define a Normal highlighting group for non-current windows. This will
    # provide a background color for shaded windows.
    if g:focalpoint_use_pmenu
        var grounds = HiGrounds(['Pmenu', 'Normal'])
        var grounds_nc = HlgetOrEmpty('Pmenu')
        grounds_nc.name = 'NormalNC'
        hlset([grounds_nc])
    else
        var grounds = HiGrounds(['Normal'])
        var grounds_nc = HlgetOrEmpty('Normal')
        grounds_nc.name = 'NormalNC'
        grounds_nc.guibg = MixColors(grounds.guifg, grounds.guibg, g:focalpoint_bg_fade)
        grounds_nc.ctermbg = HexToCterm(
            MixColors(grounds.ctermfg, grounds.ctermbg, g:focalpoint_bg_fade)
        )
        hlset([grounds_nc])
        # some of the Pmenu shades are terrible (on a few, the background
        # matches the text). If not using the Pmenu background color for
        # shading, don't use it for popup menus either. Use our custom derived
        # colors instead.
        grounds_nc.name = 'Pmenu'
        hlset([grounds_nc])
    endif

    # any background defined for EndOfBuffer will prevent empty windows (like
    # terminals with no text) from shading
    highlight EndOfBuffer guibg=NONE ctermbg=NONE
enddef


def g:FPReset(): void
    # Reset all the hi groups.
    # Call this when the colorscheme changes
    var cursor_hi = PickCurrentNowHi(g:focalpoint_cn_candidates)
    SplitHi('StatusLine')
    SplitHi('StatusLineNC')
    SplitHi(cursor_hi, 'StatusLineCN')
    DefineNormalNC()
enddef

g:FPReset()

def WinState(winid: number): number
    # Return the state of the window with winid
    # 0: focused, no splits
    # 1: unfocused, has splits (a priori)
    # 2: focused, has splits
    if winid == win_getid()
        return winnr('$') > 1 ? 2 : 0
    endif
    return 1
enddef


def g:FPSelect(
        winid: number,
        statusline: string,
        not_current: string,
        current_now: string
    ): string
    # Select a string for the statusline based on winid
    # * if win is focused, only one window visible, statusline
    # * if win is unfocused, not_current
    # * if win is focused AND there are open splits, current_now
    return [statusline, not_current, current_now][WinState(winid)]
enddef


def g:FPHiSelect(
        winid: number,
        statusline: string,
        not_current: string,
        current_now: string
    ): string
    # Select a highlight string for the statusline based on winid
    # The difference between this and FPSelect is that FPHiSelect wraps
    # highlight groups in the correct symbols to be inserted directly into an
    # statusline string.
    return g:FPSelect(
        winid,
        '%#' .. statusline .. '#',
        '%#' .. not_current .. '#',
        '%#' .. current_now .. '#',
    )
enddef

