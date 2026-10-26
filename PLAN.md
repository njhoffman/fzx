- fzx: fzf-manager and wrapper
  - i have tried multiple times to do this project, but keep restarting it because I can't figure out how to structure
    it and the general flow of the program
  - in the resources folder I have included symbolic links to my previous project attempts, along with random folders that have fzf
    scripts, specs and information
  - read through it all and suggest a project structure that achieves what I'm trying to do
  - to reiterate the main points:
    - i would like to invoke specific fzf modules by something like fzx --mode ps
    - i would like the different fzf modules to be in different folders
      - I want the script that outputs the data as a stand-alone script so it can be tested easily without being a part of the main fzf interface
      - the loading script for that module should import that basic output script
      - there should be a way to execute the scripts independently of the main fzx script/interface (it would not have
        all the bells and whistles of invoking it through fzx but it would still load in fzf with defaults)
    - i would there to be a general config that gives defaults for some of the formatting/colors/etc, but each module
      can override them with it's own config
    - i want the internals of what's going on with fzf to be easy to debug (so I can run the fzf interface and still
      know what's going on)
    - i want persistence between fzf sessions (so there can be navigation between the modules and it's subscreens)
      - an example is once the data is loaded, doing a soft reload should not reset the data, just reload the interface
        with the saved data
      - another usage would be if I wanted to reload everything but in a tmux popup instead of in the shell
      - whether to persist data or not should be known within the module, once it exits if it's not to persist the data
        (that it has temporarily saved from the load, etc) that data should be deleted
    - overall statistics kept on what module was loaded, how much time it took, etc
    - a nice to have but not necessary now: piping data to fzx, fzx would detect certain data types and automatically
       select the correct module
    - fzx without arguments loads a menu of the available modules
      - can have multiple items of the same module but with convenient arguments
      - we can start with just a description for now, but eventually I would like to show info within the context of
         where it's ran (i.e. for git commands show the number of commits, branches, how behind it is, etc)
      - if the module doesn't make sense in that directory don't show it (i.e. don't' show git commands if there is no
         repo)
      - willing to adopt some kind of caching system to make this quicker
  - integrate 'prettypath' command into files and directories to parse file icons and colors
    - if the prettypath program needs to change that's fine it's one I wrote, ~/git/prettypath
    - it would be nice if this could get integrated into vanilla fzf too if no data is being piped to it through the
      FZF_DEFAULT_COMMAND
  - added another resource (fzf-rsc), scan and add TODO items if they're not already there
  - fzfmenu contains most of the logic i'm trying to recreate for the overall workflow
    - fzf-lib.zsh handles the defalts and overrides
    - largely using environment variables for configuration but am open to better ideas
    - instead of so many config variables for the different modes, keys, colors, etc, it could perhaps just call a script
      - `FZF_MODES=modes.sh`
  - tmux specific flags: how wide, how high, positioning, etc
  - i want a key to toggle between regular fzf and tzf-tmux
    - don't use --tmux option, because that doesn't allow you to do split panes
    - will require persistence as the two scripts are separate (fzf and fzf-tmux)
  - reusable component widgets
    - look at how I'm using FZF_MODES, FZF_TOGGLES, and FZF_ACTIONS in fzf-menu

  ```
    # optional - different mode names (one active at a time)
    FZF_MODES=('install' 'remove')
    FZF_MODES_KEYS=('F1', 'F2')
    FZF_MODES_HIDE_KEYS=1
    FZF_DEFAULT_MODE=3

    # optional - different toggle names (each can be on/off)
    FZF_TOGGLES=('user' 'system')
    FZF_TOGGLES_KEYS=('S-F1', 'S-F2')

    # optional - different actions each on selected
    FZF_ACTIONS=('copy id' 'pop-out')
    FZF_ACTIONS_KEYS=('C-e', 'C-^')
    FZF_DEFAULT_ACTION="view"
    FZF_ACTIONS=(
      "view"
      "view:bat"
      "view:nvim"
      "view:popup"
    )
    FZF_ACTION_DESCRIPTIONS=(
      "view in manpager"
      "view in bat"
      "view in neovim"
      "view in popup window"
    )
  ```

  - MODES and TOGGLES would just be options provided to the script that lists the items
  - ACTIONS would be the actual commands to run, which would reside in an actions.sh script in the same directory
    - these would override the existing default actions
    - this would be another preview screen with a list of available actions
  - I want to be able to define define these per module in the config, which will render header components
  - I want them bo have configurable styles and colors too which would change if it's active or not:

   ```
   Claude   or   Claude   or  Claude
   bubble         triangle       minimal
  ```

  - or you could disable the header output but keep the functionality to pass to the list script
  - take a close look through fzfmenu, add more modules if you come across them to TODO, and formulate a plan to allow
    config driven overrides of for all of these different components
    - this is why I wanted to keep the listing functionality separate, as well as the actions
    - even if all the sugar wrapping (mostly driven by config) is absent, there should still be some base functionality
        in the fzf interface
  - would eventually like to show a help screen that lists all of these different parameters for the module, including
    keybindings
    - even cooler would be parsing the FZF_DEFAULT_OPTS and figuring out what keys are assigned, so we can show what keys
      are available for mapping to different widgets, actions, etc
  - would like to define the prompt icon per module, as well as using the load transform to indicate what it should look
    like while loading and then while loaded (which is why I liked my default prompt icon that was dim when loading and
    bold when loaded)
  - when debugging I would like to optionally trace events like start, resize, result, etc
  - update TODO with these new specs
