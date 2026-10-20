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
