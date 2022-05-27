## lbry-viewer

A lightweight application (fork of [pipe-viewer](https://github.com/trizen/pipe-viewer)) for searching and playing videos from [LBRY](https://lbry.com/), using the [Librarian](https://codeberg.org/librarian/librarian) frontend.

### STATUS

The application is in the early stages of development. Some functionality not implemented yet.

### lbry-viewer

* command-line interface to LBRY.

![lbry-viewer](https://user-images.githubusercontent.com/614513/97738550-6d0faf00-1ad6-11eb-84ec-d37f28073d9d.png)

### gtk-lbry-viewer

* GTK+ interface to LBRY.

![gtk-lbry-viewer](https://user-images.githubusercontent.com/614513/127567550-d5742dee-593c-4167-acc4-6d80fd061ffc.png)


### AVAILABILITY

* Arch Linux (AUR): https://aur.archlinux.org/packages/lbry-viewer-git/

### TRY

For trying the latest commit of `lbry-viewer`, without installing it, execute the following commands:

```console
    cd /tmp
    wget https://github.com/trizen/lbry-viewer/archive/main.zip -O lbry-viewer-main.zip
    unzip -n lbry-viewer-main.zip
    cd lbry-viewer-main/bin
    ./lbry-viewer
```

### INSTALLATION

To install `lbry-viewer`, run:

```console
    perl Build.PL
    sudo ./Build installdeps
    sudo ./Build install
```

To install `gtk-lbry-viewer` along with `lbry-viewer`, run:

```console
    perl Build.PL --gtk
    sudo ./Build installdeps
    sudo ./Build install
```

### DEPENDENCIES

#### For lbry-viewer:

* [libwww-perl](https://metacpan.org/release/libwww-perl)
* [LWP::Protocol::https](https://metacpan.org/release/LWP-Protocol-https)
* [Data::Dump](https://metacpan.org/release/Data-Dump)
* [JSON](https://metacpan.org/release/JSON)
* [HTML::Tree](https://metacpan.org/release/HTML-Tree)

#### For gtk-lbry-viewer:

* [Gtk3](https://metacpan.org/release/Gtk3)
* [File::ShareDir](https://metacpan.org/release/File-ShareDir)
* \+ the dependencies required by lbry-viewer.

#### Build dependencies:

* [Module::Build](https://metacpan.org/pod/Module::Build)

#### Optional dependencies:

* Local cache support: [LWP::UserAgent::Cached](https://metacpan.org/release/LWP-UserAgent-Cached)
* Better STDIN support (+history): [Term::ReadLine::Gnu](https://metacpan.org/release/Term-ReadLine-Gnu)
* Faster JSON deserialization: [JSON::XS](https://metacpan.org/release/JSON-XS)
* Fixed-width formatting: [Unicode::LineBreak](https://metacpan.org/release/Unicode-LineBreak) or [Text::CharWidth](https://metacpan.org/release/Text-CharWidth)
* [yt-dlp](https://github.com/yt-dlp/yt-dlp) or [youtube-dl](https://github.com/ytdl-org/youtube-dl).


### PACKAGING

To package this application, run the following commands:

```console
    perl Build.PL --destdir "/my/package/path" --installdirs vendor [--gtk]
    ./Build test
    ./Build install --install_path script=/usr/bin
```

### LIBRARIAN INSTANCES

To use a specific Librarian instance, like [lbry.vern.cc](https://lbry.vern.cc/), pass the `--api=HOST` option:

```console
    lbry-viewer --api=lbry.vern.cc
```

To make the change permanent, set in the configuration file:

```perl
    api_host => "lbry.vern.cc",
```

When `api_host` is set to `"auto"`, `lbry-viewer` picks a random invidious instance from [codeberg.org/librarian/librarian](https://codeberg.org/librarian/librarian#clearnet).

### SUPPORT AND DOCUMENTATION

After installing, you can find documentation with the following commands:

    man lbry-viewer
    perldoc WWW::LbryViewer

### LICENSE AND COPYRIGHT

Copyright (C) 2012-2022 Trizen

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See https://dev.perl.org/licenses/ for more information.
