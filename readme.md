
# Plugins to make or improve widescreen resolutions support in PC games, add more features and fix bugs.
‎
A project deploys its built `.asi` into the game folder its key names in a `.env` file in the repository root, so that the paths of a machine stay out of the repository (the file is ignored by git, a game the file does not name is simply not deployed), for example:

The build copies the plugin into the `scripts` folder of that game (`plugins` where the game has one), and starts the game from there when debugging. Only a plugin that is already installed is replaced. The keys of all projects are listed in the `.env` file of a working copy, where a key is the name of the game folder in upper case.

The usage is as simple as inserting the files into game's root directory. Uninstalling is as easy as that too, delete the files and you are done.

Plugins will come with an [Ultimate ASI Loader](https://github.com/ThirteenAG/Ultimate-ASI-Loader) that is capable of generating crash dumps and crash logs.
