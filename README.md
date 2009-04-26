Colloqueer
==========
Colloqueer is an IRC client that can use Colloquy themes. Right now it is
only tested with the Buttesfire theme. The Buttesfire theme works for the
most part, with a few minor tweaks to the css. Things will work much nicer
once certain features are added to the Gtk+ port of WebKit (specifically DOM
access.)

Install
-------
* perl Makefile.PL
* make
* make install (probably want to do this as root)
* copy and edit colloqueer.example.yaml to your home directory as .colloqueer.yaml

Requirements
------------
* Moose
* Gtk2
* Gtk2::WebKit
* Gtk2::Spell
* XML::LibXML
* XML::LibXSLT
* POE
* POE::Loop::Glib
* POE::Component::IRC
* YAML::Any
* Template
* DateTime

Colloqueer needs ruby until I port irc2html.rb to perl.
