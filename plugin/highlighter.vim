" Utility: highlighter.vim
" Author:  Dave Larson       silverleaf at bluebottle dot com
" Version: 1.3
" $Date: 2007/08/09 21:39:06 $
"
" This plugin gives you the capability to mark up your files as if you had a
" highlighter.
"
" It's a really useful aid for inspecting log files and marking important
" sections in source code and documents (even vim help files).
"
" The highlights are remembered, even after you close the file. You can also
" distribute the marks so others can see the highlights you made - they are
" saved in <path_to_your_file>/.<filename>_highlight.vim (they'll need this
" plugin to see them, however).
"
" Settings:
" Look under the Plugin->Highlighter menu for color settings. These settings
" will be remembered between sessions and used in all open vim windows.
"
" Highlighters:
" (These commands can be typed on the command line, I recommend creating
" your own mappings for these.)
"
"   :WordHighlighter
"        Highlight the word under the cursor in the current color mode.  Call
"        WordHighlighter again before moving the cursor to replace the color
"        with a new one if you don't like the color that was chosen (assuming
"        that you've configured the colors to be generated randomly).
"
"   :SelectionHighlighter
"        Highlight the visually selected block in the current color mode.
"        Works like WordHighlighter.
"
"   :SearchPatternHighlighter
"        Highlight the current search pattern (@/). You can also use this
"        mechanism to highlight an expression.
"
"   :ClearCurrentHighlighter
"        Clear the current highlight. The current highlight is the one under the
"        cursor or the previous highlight (if the cursor hasn't moved).
"
"   :ClearAllHighlighters
"        Clear all highlighter marks made in this file. There is a menu option
"        for restoring the colors from the last save if you didn't mean to do
"        that.  Marks are saved when you leave the buffer so just don't leave
"        the buffer first!
"
"   :ConfigureHighlighter
"        Open the highlighter configuration window. From here you can
"        configure how highlighter colors are determined and whether the
"        highlights will work on all matching text or on the selected text
"        only. New favorite colors can be added by placing the cursor over a
"        highlighter, then select the Plugin->Highlighter->Add Current To
"        Favorites option.
"
" Troubleshooting: (Highlighting isn't perfect)
" - The highlighting only works with gvim and 'syntax' must be on.
" - The highlighter will be slower for files that have complex syntax
"   highlighting (e.g. vim files)
" - The highlighter doesn't work in all cases because syntax keywords don't
"   always like to be highlighted over. If the highlighter doesn't appear like
"   it should, try starting the highlighter at different spots.
"
" Consider This:
" We don't see the world through glasses... no lens separates you from
" reality. Your perspective is only limited by your knowledge. The more you
" know the more you see.
"
" Question those who question reality.
"
" Thanks To:
" Eiji Kumiai for submitting his diminutive dynamicsyntax script which sparked
" the idea for writing this one.
"
" TODO:
" ADD: a window that lists all of the file's highlights. Pressing enter in
"   this window takes you to the pattern (useful for jumping to important
"   sections in the doc); pressing "d" deletes the mark (this is useful to
"   delete a highlight that no longer shows up in the file because the text
"   has changed).
"
" ADD: For "use current highlighter" - also pick up non-highlighter highlights.
"   (this may be more difficult than it sounds)
"
" ADD: May have to name the config file - to synchronize many config windows
" that are open at once. Or the buffer could be closed automatically when the
" cursor leaves, although I can't guarantee that the user just doesn't go to
" another window and open another one. If not, then be sure that it isn't the
" only window open when the source file closes.
"
" ADD: add code to match/ignore case. See
" help syn-case
"  Tho this would require that the case is saved.



if (!has("syntax") || !has("gui"))
   finish
endif

" Constants {{{1
let s:mode_new       = 0 | lockvar s:mode_new
let s:mode_cycle     = 1 | lockvar s:mode_cycle
let s:mode_favorite  = 2 | lockvar s:mode_favorite
let s:default_color  = "guifg=black guibg=lightyellow gui=bold" | lockvar s:default_color
let s:version        = 2 | lockvar s:version
let s:attributes     = [ "bold", "underline", "undercurl", "reverse", "italic", "standout" ] | lockvar s:attributes
" }}}1
" Startup/Mappings {{{1
command        WordHighlighter          call <SID>highlight(expand("<cword>"), "")
command -range SelectionHighlighter     call <SID>highlight(@*, "v")
command        SearchPatternHighlighter call <SID>highlight(@/, "s")
command        ClearAllHighlighters     call <SID>clearAll()
command        ClearCurrentHighlighter  call <SID>clearCurrentHighlighter()
command        ConfigureHighlighter     call <SID>configure()
au GUIEnter * call s:startup()
function s:startup() " {{{2

   au BufRead * call s:checkForHighlightFile()
   let s:current_color = s:default_color
   let s:cursor_moved = 1
   set guioptions+=a

   call s:createMenu()

   " restore the settings file
   let s:settingsfile = findfile(".highlighter_settings.vim", &rtp)
   if (empty(s:settingsfile))
      " a settings file doesn't exist - create it.
      call s:createSettingsFile()
   else
      let s:settingsfile = fnamemodify(s:settingsfile, ":p")
      call s:readSettingsFile()
   endif
   let s:ID = 0
endfunction " }}}2
function s:bufferStarted() " {{{2
   let b:started = 1
   let b:used = {}
   let b:nextfav = 0
   let b:highlighting_changed = 0

   au Syntax <buffer> call s:redraw()
   " Note: BufLeave doesn't trigger when exiting so we need VimLeave too
   au BufLeave,VimLeave <buffer> call s:saveFileHighlighting(expand("<afile>"))
   au FocusGained <buffer> call s:checkSettingsFile()
   au CursorMoved <buffer> let s:cursor_moved = 1
endfunction " }}}2
" }}}1
" Highlighting {{{1
function s:clear(synName) " {{{2
   exec "syn clear ".a:synName
endfunction " }}}2
function s:draw(name) " {{{2
   let [color, pattern] = b:used[a:name]

   for p in split(pattern, '\n')
      exec "syn match" a:name '"'.p.'" containedin=ALL'
   endfor
   exec "hi" a:name color
endfunction " }}}2
function s:redrawLastPattern(color) " {{{2
   call s:clear(b:current_ID)
   let b:used[b:current_ID][0] = a:color
   call s:draw(b:current_ID)
endfunction " }}}2
function s:removeID(ID) " {{{2
   call s:clear(a:ID)
   call remove(b:used, a:ID)
endfunction " }}}2
function s:clearAll() " {{{2
   if (exists("b:used") && !empty(b:used))
      call s:clear(join(keys(b:used), " "))
      let b:used = {}

      let b:highlighting_changed = 1
      let s:cursor_moved = 1
   endif
endfunction " }}}2
function s:clearCurrentHighlighter() " {{{2
   let synName = s:getSyntaxNameUnderCursor()
   if (!s:cursor_moved)
      " The current highlighter may not be under the cursor if we highlighted
      " the current search pattern.
      call s:removeID(b:current_ID)
   elseif (synName =~ '^Highlighter')
      call s:removeID(synName)
   else
      return
   endif

   let b:highlighting_changed = 1
   let s:cursor_moved = 1
endfunction " }}}2
function s:highlight(text, opts) " {{{2
   if (empty(a:text))
      return
   elseif (!exists("b:started"))
      call s:bufferStarted()
   endif

   let color = s:chooseColor()
   if (empty(color)) | return | endif
   let s:current_color = color

   if (!s:cursor_moved)
      call s:redrawLastPattern(s:current_color)
      return
   endif

   if (a:opts =~ "s")
      let pattern = a:text
   else
      let pattern = escape(a:text, '."\[]*')
      if (!s:settings["search"])
         " Add line numbers to the patterns
         if (a:opts =~ "v")
            let [line, pats] = [line("'<"), split(pattern, '\n')]
         else
            let [line, pats] = [line("."), [pattern]]
         endif

         let newpats = []
         for pat in pats
            if (!empty(pat))
               call add(newpats, '\%'.line.'l'.pat)
            endif
            let line += 1
         endfor
         let pattern = join(newpats, "\n")
      endif
   endif

   if (!empty(pattern))
      let b:current_ID = s:newHighlighter(s:current_color, pattern)
      let b:highlighting_changed = 1
      let s:cursor_moved = 0
   endif
endfunction " }}}2
function s:newHighlighter(color, pat) " {{{2
   let ID = "Highlighter".s:ID
   let b:used[ID] = [a:color, a:pat]
   call s:draw(ID)
   let s:ID += 1
   return ID
endfunction " }}}2
function s:chooseColor() " {{{2
   " Determine the highlighter to use
   if (s:settings["mode"] == s:mode_new)
      let [c, a] = [[],[]]
      if (s:settings["random_foreground"])   | call add(c, "guifg=#".s:genRandColor()) | endif
      if (s:settings["random_background"])   | call add(c, "guibg=#".s:genRandColor()) | endif
      if (s:settings["random_undercurl"])    | call add(c, "guisp=#".s:genRandColor()) | endif
      for attr in s:attributes
         if (s:settings[attr])               | call add(a, attr) | endif
      endfor

      if (empty(c) && empty(a))
         echoerr "Can't create a new highlighter because all the settings are off!"
         return ""
      endif
      if (empty(a))
         call add(a, "NONE")
      endif
      return join(c, " ")." gui=".join(a, ",")
   elseif (s:settings["mode"] == s:mode_cycle)
      if (empty(s:favorites))
         echoerr "Can't cycle through favorites - no favorites are defined!"
         return ""
      endif
      let name = get(s:favlist, b:nextfav, "default")
      echo "Highlighting with" name
      let color = s:favorites[name]
      let b:nextfav += 1
      if (b:nextfav >= len(s:favlist))
         let b:nextfav = 0
      endif
      return color
   elseif (s:settings["mode"] == s:mode_favorite)
      return get(s:favorites, s:settings["selectedfavorite"], "default")
   endif
endfunction " }}}2
" }}}1
" Highlighting file {{{1
function s:saveFileHighlighting(file) " {{{2
   " if (a:file != expand("%") || !b:highlighting_changed)
   if (a:file != @% || !b:highlighting_changed)
      " if the current buffer isn't the same as this one then vim is exiting
      " and the settings have already been saved so we can just exit. Also,
      " don't save if highlighting hasn't changed since list save.
      return
   endif

   let file = s:getHighlightFile(a:file)
   if (empty(file))
      " Don't save highlighting for a file without a name
      let s:cursor_moved = 1
      return
   endif

   " Note: Don't use 'string(b:used)' because these dictionaries can get very
   " large - so add them one by one
   let save = []
   for v in values(b:used)
      call add(save, string(v))
   endfor
   if (empty(save))
      call delete(file)
   else
      call insert(save, s:version)
      call writefile(save, file)
   endif

   let b:highlighting_changed = 0
   let s:cursor_moved = 1
endfunction " }}}2
function s:readHighlightFile() " {{{2
   if (!filereadable(b:highlights))
      return
   endif

   let items = readfile(b:highlights)

   let l:version = remove(items, 0)
   if (l:version != s:version)
      echoerr "Uh oh. The saved highlighting for this file doesn't match your highlighter.vim version. Please delete" b:highlights "and start again."
   endif

   let b:used = {}
   for i in items " each item in the List is a string, so convert each string to a list
      exec "let [color, pat] =" i
      let b:current_ID = s:newHighlighter(color, pat)
   endfor

   let b:highlighting_changed = 0
endfunction " }}}2
function s:redraw() " {{{2
   for ID in keys(b:used)
      call s:draw(ID)
   endfor
endfunction " }}}2
function s:getHighlightFile(f) " {{{2
   if (empty(a:f))
      return ""
   endif
   return fnamemodify(a:f, ":p:h")."/.".fnamemodify(a:f, ":t")."_highlight.vim"
endfunction " }}}2
function s:checkForHighlightFile() " {{{2
   if (exists("b:started"))
      return
   endif
   " let b:highlights = s:getHighlightFile(expand("%"))
   let b:highlights = s:getHighlightFile(@%)
   if (!filereadable(b:highlights))
      return
   endif

   call s:bufferStarted()
   call s:readHighlightFile()
endfunction " }}}2
" }}}1
" Settings File {{{1
function s:writeSettingsFile() " {{{2
   let save = []
   call add(save, 'let s:saved_version = '.s:version)
   call add(save, 'let s:settings = '.string(s:settings))
   call add(save, 'let s:favorites = '.string(s:favorites))
   call writefile(save, s:settingsfile)
   let s:settings_file_mod_time = getftime(s:settingsfile)
endfunction " }}}2
function s:readSettingsFile() " {{{2
   call s:readVars(s:settingsfile)
   if (s:saved_version != s:version)
      redraw!
      echoerr "Uh oh. Your highlighter settings doesn't match your highlighter.vim version. Please delete" s:settingsfile "and start again."
   endif
   let s:settings_file_mod_time = getftime(s:settingsfile)

   call s:update_favlist()
endfunction " }}}2
function s:createSettingsFile() " {{{2
   for d in split(&rtp, ",")
      if (isdirectory(d)) | break | endif
   endfor
   let s:settingsfile = d."/.highlighter_settings.vim"

   " default settings
   let s:settings = {}
   let s:settings["random_background"] = 1
   let s:settings["random_foreground"] = 1
   let s:settings["random_undercurl"] = 0
   let s:settings["mode"] = s:mode_new
   let s:settings["selectedfavorite"] = "default"
   let s:settings["search"] = 0
   for attr in s:attributes
      let s:settings[attr] = 0
   endfor

   let s:favorites = {}
   let s:favorites["Beet Juice"] = "guifg=#EF6C7F guibg=#3A144C gui=bold"
   let s:favorites["Bold Only"] = "guifg=NONE guibg=NONE gui=bold"
   let s:favorites["Easy Blue"] = "guifg=NONE guibg=#1F4287 gui=NONE"
   let s:favorites["Ghost Blue"] = "guifg=#1A82A8 guibg=#0901C1 gui=bold"
   let s:favorites["Grape Sucker"] = "guifg=#FA9EF4 guibg=#242A55 gui=underline"
   let s:favorites["Grass"] = "guifg=#D6E793 guibg=#3E6C30 gui=NONE"
   let s:favorites["Ivy League"] = "guifg=#F1D05F guibg=#132554 gui=bold"
   let s:favorites["Lemon Tart"] = "guifg=#A1ED09 guibg=#207A9C gui=NONE"
   let s:favorites["Pink Lemonaide"] = "guifg=#D0901B guibg=#683A48 gui=NONE"
   let s:favorites["Red Streak"] = "guifg=#BBE8E8 guibg=#690B01 gui=bold"
   let s:favorites["Yellow Pen"] = "guifg=#0F0932 guibg=#DFF611 gui=bold"
   let s:favorites["Yellow Text"] = "guifg=#F8D403 guibg=NONE gui=bold"
   let s:favorites["current"] = s:default_color
   let s:favorites["default"] = s:default_color

   call s:update_favlist()
   call s:writeSettingsFile()
endfunction " }}}2
function s:checkSettingsFile() " {{{2
   if (!filereadable(s:settingsfile))
      call s:writeSettingsFile()
   elseif (getftime(s:settingsfile) > s:settings_file_mod_time)
      call s:readSettingsFile()
   endif
endfunction " }}}2
" }}}1
" Utilities {{{1
function s:readVars(file) " {{{2
   " NOTE: can't use :source here because s:variables defined in the settings
   " file are not accessible to the parent script (by definition). So execute
   " the lines in this script context instead.
   let lines = readfile(a:file)
   for l in lines | exec l | endfor
   return len(lines)
endfunction " }}}2
function s:getSyntaxNameUnderCursor() " {{{2
   return synIDattr(synID(line('.'), col('.'), 0), 'name')
endfunction " }}}2
function s:update_favlist() " {{{2
   let favs = copy(s:favorites)
   call remove(favs, "current")
   call remove(favs, "default")
   let s:favlist = sort(keys(favs))
endfunction " }}}2
" }}}1
" Config Window / Menu {{{1
function s:configure() " {{{2
   new
   setl nobuflisted noswapfile bufhidden=delete
   call s:bufferStarted()

   let lines = []
   call add(lines, "<cr> - change / select the option under the cursor")
   call add(lines, "<r>  - remove the favorite color under the cursor (if any)")
   call add(lines, "<q>  - quit")
   call add(lines, s:displaySearch())
   call extend(lines, s:displayMode())

   call setline(1, lines)
   setl nomodified nomodifiable

   if winheight(".") > line("$")
      exec "resize" line("$")
   endif
   setl fdm=manual
   normal! zR

   call s:newHighlighter("guifg=red gui=bold", "OFF")
   for text in ["ON", "all matching text", "selected text only", "New", "Cycle", 'Favorite\>', '<.*>']
      call s:newHighlighter("guifg=green gui=bold", text)
   endfor

   noremap <buffer> <silent>               q :q!<cr>
   noremap <buffer> <silent>               r :call <SID>r()<cr>
   noremap <buffer> <silent> <special> <esc> :q!<cr>
   noremap <buffer> <silent> <special>  <cr> :call <SID>CR()<cr>
endfunction " }}}2
function s:CR() " {{{2
   setl modifiable
   let line = getline(".")
   if (line =~ "Current Mode")
      normal! "_dG
      let s:settings["mode"] = (s:settings["mode"] + 1) % 3
      call append(".", s:displayMode())
      normal! j
      if winheight(".") != line("$")
         exec "resize" line("$")
      endif
   elseif (line =~ "Highlight")
      let s:settings["search"] = !s:settings["search"]
      call setline(".", s:displaySearch())
   elseif (s:settings["mode"] == s:mode_favorite)
      let name = line[3:-1]
      if (has_key(s:favorites, name))
         normal! ^
         let synID = s:getSyntaxNameUnderCursor()
         q!
         exec "echohl" synID
         echo "Okay - Using this highlighter"
         echohl NONE
         let s:settings["selectedfavorite"] = name
      endif
   elseif (s:settings["mode"] == s:mode_new)
      if (line =~ "ON:")
         let val = 0
      elseif (line =~ "OFF:")
         let val = 1
      else
         let val = -1
      endif
      if (val != -1)
         let attr = matchstr(line, '\w\+: \zs\w\+\ze')
         let s:settings[attr] = val
         call setline(".", "   ".((val)?" ON":"OFF").": ".attr)
      endif
   endif
   call s:writeSettingsFile()
   setl nomodified nomodifiable
endfunction " }}}2
function s:r() " {{{2
   if (s:settings["mode"] == s:mode_favorite)
      let name = getline(".")[3:-1]
      if (has_key(s:favorites, name))
         setl modifiable
         normal! ^
         call remove(s:favorites, name)
         normal! "_dd

         call s:update_favlist()

         if (!has_key(s:favorites, s:settings["selectedfavorite"]))
            " just removed the color that is current. Replace it w/something else.
            let s:settings["selectedfavorite"] = get(s:favlist, 0, "default")
         endif
         call s:writeSettingsFile()
         setl nomodified nomodifiable
      endif
   endif
endfunction " }}}2
function s:displaySearch() " {{{2
   if (s:settings["search"])
      return "- Highlight all matching text"
   else
      return "- Highlight selected text only"
   endif
endfunction
function s:displayMode() " {{{2
   let lines = []
   if (s:settings["mode"] == s:mode_new)
      call add(lines, "- Current Mode: Generate New Highlighters")
      for attr in ["random_foreground", "random_background", "random_undercurl"]
         call add(lines, ((s:settings[attr]) ? "    ON: " : "   OFF: ").attr)
      endfor
      for attr in s:attributes
         call add(lines, ((s:settings[attr]) ? "    ON: " : "   OFF: ").attr)
         call s:newHighlighter("guisp=yellow gui=".attr, attr)
      endfor
   elseif (s:settings["mode"] == s:mode_cycle)
      call add(lines, "- Current Mode: Cycle Through Favorites")
   elseif (s:settings["mode"] == s:mode_favorite)
      call add(lines, "- Current Mode: Use Favorite Color (Select Color)")
      for name in s:favlist
         call add(lines, "   ".name)
         call s:newHighlighter(s:favorites[name], escape(name, ' '))
      endfor
   endif
   return lines
endfunction " }}}2
function s:createMenu() " {{{2
   let m = 'menu <silent> Plugin.&Highlighter'

   exec m.'.&Add\ Current\ To\ Favorites :call <SID>addToFavorites()<cr>'
   exec m.'.-Sep- :'

   exec m.'.Use\ &Current\ Highlighter :call <SID>useCurrentHighlighter()<cr>'
   exec m.'.-Sep2- :'

   exec m.'.&Restore\ Highlighting :call <SID>readHighlightFile()<cr>'
endfunction " }}}2
function s:addToFavorites() " {{{2
   let ID = s:getSyntaxNameUnderCursor()
   if (ID !~ '^Highlighter')
      echohl ERROR
      echo "Please put cursor over a highlighter to add"
      echohl NONE
      return
   endif
   exec "echohl" ID
   let name = input("Saving this highlighter - Name: ")
   echohl NONE
   if (!empty(name))
      let s:favorites[name] = b:used[ID][0]
      call s:writeSettingsFile()
   endif
endfunction " }}}2
function s:useCurrentHighlighter() " {{{2
   let synName = s:getSyntaxNameUnderCursor()
   if (synName =~ '^Highlighter')
      exec "echohl" synName
      echo "Okay - Using this highlighter"
      echohl NONE
      let s:favorites["current"] = b:used[synName][0]
   elseif (exists("b:current_ID"))
      exec "echohl" b:current_ID
      echo "Okay - Using the current highlighter"
      echohl NONE
      let s:favorites["current"] = b:used[b:current_ID][0]
   else
      echo "Okay - Using the default color"
      let s:favorites["current"] = s:default_color
   endif
   let s:settings["mode"] = s:mode_favorite
   let s:settings["selectedfavorite"] = "current"
   call s:writeSettingsFile()
endfunction " }}}2
" }}}1
" Random Number Generation {{{1
function s:genBSDRandNum() " {{{2
   " This is based on the BSD rand() generator.
   " x_{n+1} = (a x_n + c) mod m
   " with a = 1103515245, c = 12345 and m = 2^31. The seed specifies the initial
   " value, x_1. The period of this generator is 2^31, and it uses 1 word of
   " storage per generator.
   if (!exists("b:x_n"))
      let b:x_n = localtime() " generate seed
   endif
   let b:x_n = (1103515245*b:x_n + 12345) % 0x80000000
   return b:x_n
endfunction " }}}2
function s:genRandColor() " {{{2
   let num = s:genBSDRandNum()

   " turn the number into a color
   return printf("%06X", max([num, -num]) % 0x1000000)
endfunction " }}}2
" }}}1



" vim: fdm=marker:sw=3
